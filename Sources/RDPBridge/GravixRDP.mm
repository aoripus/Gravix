#import "GravixRDP.h"
#import <QuartzCore/QuartzCore.h>
#include "TransferSafety.hpp"
#include <freerdp/freerdp.h>
#include <freerdp/client.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/client/channels.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/client/disp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/graphics.h>
#include <freerdp/codec/color.h>
#include <freerdp/utils/cliprdr_utils.h>
#include <freerdp/version.h>
#include <freerdp/input.h>
#include <winpr/synch.h>
#include <winpr/wlog.h>
#include <winpr/shell.h>
#include <atomic>
#include <mutex>
#include <deque>
#include <functional>
#include <vector>
#include <string>
#include <set>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

struct Engine;
struct GRContext { rdpClientContext common; Engine *engine; };
struct LocalFile { std::string path, name; uint64_t size; bool directory; dev_t device; ino_t inode; };
struct RemoteFile { std::string name; uint64_t size; bool directory; };

@interface GRDesktopView ()
@property(nonatomic, strong) NSData *pixels;
@property(nonatomic) NSInteger pixelWidth;
@property(nonatomic) NSInteger pixelHeight;
@property(nonatomic, strong) NSMutableAttributedString *marked;
@property(nonatomic) NSEventModifierFlags oldModifiers;
@property(nonatomic, strong) NSCursor *remoteCursor;
- (void)showPixels:(NSData *)data width:(int)width height:(int)height stride:(int)stride;
- (void)scheduleResize;
@end

@interface GRSession () {
@public
    Engine *_engine;
    NSDictionary *_configuration;
    NSString *_password;
    NSTimer *_clipboardTimer;
    NSInteger _pasteboardChange;
    BOOL _started;
}
@property(nonatomic, readwrite) GRDesktopView *desktopView;
- (void)emit:(NSString *)event detail:(NSString *)detail;
- (void)pollClipboard;
- (void)setRemoteText:(NSString *)text;
- (void)sendScan:(uint16_t)scan down:(BOOL)down;
- (void)sendUnicode:(NSString *)text;
- (void)sendMouse:(uint16_t)flags x:(int)x y:(int)y;
- (void)resizeWidth:(int)width height:(int)height;
- (void)releaseKeys;
@end

struct Engine {
    __unsafe_unretained GRSession *owner;
    rdpContext *ctx = nullptr;
    std::mutex lifecycle, queueMutex, frameMutex;
    std::deque<std::function<void()>> commands;
    std::atomic<bool> stopping{false}, connected{false}, frameQueued{false};
    NSData *latestFrame = nil;
    int frameW = 0, frameH = 0, frameStride = 0;
    CliprdrClientContext *clip = nullptr;
    DispClientContext *disp = nullptr;
    bool dispReady = false, clipReady = false;
    int desiredW = 1440, desiredH = 900, sentW = 0, sentH = 0;
    bool dynamic = true;
    std::vector<LocalFile> localFiles;
    NSData *localText = nil;
    uint32_t remoteFilesID = 0, remoteTextID = 0, serverFlags = 0;
    uint64_t clipboardEpoch = 0, pendingEpoch = 0;
    int pendingFormat = 0; // 1 = Unicode, 2 = file descriptors. One request at a time.
    bool receiving = false;
    std::vector<RemoteFile> remoteFiles;
    size_t receiveIndex = 0;
    uint64_t offset = 0, transferred = 0, totalBytes = 0;
    uint32_t stream = 0, expectedStream = 0, expectedBytes = 0;
    int outputFD = -1;
    NSURL *receiveRoot = nil;
    NSURL *receiveDestination = nil;
    std::set<uint16_t> heldKeys;
    double requestTime = 0, progressTime = 0;
    explicit Engine(GRSession *session) : owner(session) {}
    void enqueue(std::function<void()> fn) {
        std::lock_guard<std::mutex> lock(queueMutex);
        if (!stopping) commands.push_back(std::move(fn));
    }
    void drain() {
        std::deque<std::function<void()>> current;
        { std::lock_guard<std::mutex> lock(queueMutex); current.swap(commands); }
        for (auto &fn : current) if (!stopping) fn();
    }
    void event(NSString *type, NSString *message) { [owner emit:type detail:message]; }
    void finishTransfer(NSString *error) {
        if (outputFD >= 0) { close(outputFD); outputFD = -1; }
        const bool hadTransfer = receiving;
        receiving = false;
        expectedStream = 0;
        if (error && receiveRoot) [[NSFileManager defaultManager] removeItemAtURL:receiveRoot error:nil];
        if (error && hadTransfer) event(@"transfer", error);
        receiveRoot = nil;
        remoteFiles.clear();
    }
    void advertise() {
        if (!clip || !clipReady) return;
        CLIPRDR_FORMAT formats[2] = {};
        UINT32 count = 0;
        if (!localFiles.empty()) { formats[count].formatId = 0xC001; formats[count++].formatName = const_cast<char*>("FileGroupDescriptorW"); }
        else if (localText) formats[count++].formatId = CF_UNICODETEXT;
        CLIPRDR_FORMAT_LIST list = {}; list.numFormats = count; list.formats = formats;
        (void)clip->ClientFormatList(clip, &list);
    }
    void requestText() {
        if (!clip || !remoteTextID || remoteFilesID || pendingFormat) return;
        pendingFormat = 1; pendingEpoch = clipboardEpoch;
        CLIPRDR_FORMAT_DATA_REQUEST request = {}; request.requestedFormatId = remoteTextID;
        requestTime = [NSDate timeIntervalSinceReferenceDate];
        if (clip->ClientFormatDataRequest(clip, &request) != CHANNEL_RC_OK) pendingFormat = 0;
    }
    void requestChunk();
    void startReceive(NSURL *destination) {
        if (!clip || !remoteFilesID) { event(@"transfer", @"请先在 Windows 中复制文件，然后再接收。"); return; }
        if (receiving || pendingFormat) { event(@"transfer", @"剪贴板正在处理，请稍后再试。"); return; }
        receiving = true; receiveDestination = destination;
        pendingFormat = 2; pendingEpoch = clipboardEpoch;
        CLIPRDR_FORMAT_DATA_REQUEST request = {}; request.requestedFormatId = remoteFilesID;
        requestTime = [NSDate timeIntervalSinceReferenceDate];
        if (clip->ClientFormatDataRequest(clip, &request) != CHANNEL_RC_OK) { pendingFormat = 0; finishTransfer(@"无法读取 Windows 文件剪贴板。"); }
        else event(@"transfer", @"正在读取文件列表…");
    }
    void resize() {
        if (!dynamic || !disp || !dispReady || (sentW == desiredW && sentH == desiredH)) return;
        DISPLAY_CONTROL_MONITOR_LAYOUT layout = {};
        layout.Flags = DISPLAY_CONTROL_MONITOR_PRIMARY;
        layout.Width = desiredW; layout.Height = desiredH;
        layout.PhysicalWidth = 340; layout.PhysicalHeight = 210;
        layout.DesktopScaleFactor = 100; layout.DeviceScaleFactor = 100;
        if (disp->SendMonitorLayout(disp, 1, &layout) == CHANNEL_RC_OK) { sentW = desiredW; sentH = desiredH; }
    }
};
static Engine *engine(rdpContext *ctx) { return reinterpret_cast<GRContext*>(ctx)->engine; }
static Engine *engine(CliprdrClientContext *clip) { return static_cast<Engine*>(clip->custom); }
static NSString *str(const char *s) { return s ? ([NSString stringWithUTF8String:s] ?: @"") : @""; }

void Engine::requestChunk() {
    while (receiving && receiveIndex < remoteFiles.size()) {
        auto &file = remoteFiles[receiveIndex];
        NSString *relative = [str(file.name.c_str()) stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        NSURL *url = [receiveRoot URLByAppendingPathComponent:relative];
        NSError *error = nil;
        if (file.directory) {
            if (![[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) { finishTransfer(@"无法创建接收文件夹。"); return; }
            receiveIndex++; continue;
        }
        if (outputFD < 0) {
            if (![[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) { finishTransfer(@"无法创建接收目录。"); return; }
            outputFD = open(url.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
            if (outputFD < 0) { finishTransfer(@"无法安全创建文件，传输已取消。"); return; }
        }
        if (offset == file.size) { close(outputFD); outputFD = -1; offset = 0; receiveIndex++; continue; }
        CLIPRDR_FILE_CONTENTS_REQUEST request = {};
        request.streamId = ++stream; request.listIndex = (UINT32)receiveIndex;
        request.dwFlags = FILECONTENTS_RANGE;
        request.nPositionLow = (UINT32)offset; request.nPositionHigh = (UINT32)(offset >> 32);
        request.cbRequested = (UINT32)std::min<uint64_t>(128 * 1024, file.size - offset);
        expectedStream = request.streamId; expectedBytes = request.cbRequested;
        requestTime = [NSDate timeIntervalSinceReferenceDate];
        if (clip->ClientFileContentsRequest(clip, &request) != CHANNEL_RC_OK) finishTransfer(@"文件请求失败。");
        return;
    }
    if (receiving) {
        NSURL *finished = receiveRoot;
        receiving = false; receiveRoot = nil; expectedStream = 0;
        GRSession *session = owner;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<NSURL*> *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:finished includingPropertiesForKeys:nil options:0 error:nil];
            NSPasteboard *pb = NSPasteboard.generalPasteboard; [pb clearContents]; [pb writeObjects:urls ?: @[]]; session->_pasteboardChange = pb.changeCount;
            [session emit:@"received" detail:finished.path];
        });
    }
}

static UINT clipReady(CliprdrClientContext *clip, const CLIPRDR_MONITOR_READY *) {
    auto e = engine(clip);
    e->enqueue([e] {
        if (!e->clip) return;
        CLIPRDR_GENERAL_CAPABILITY_SET general = {};
        general.capabilitySetType = CB_CAPSTYPE_GENERAL; general.capabilitySetLength = 12;
        general.version = CB_CAPS_VERSION_2;
        general.generalFlags = CB_USE_LONG_FORMAT_NAMES | CB_STREAM_FILECLIP_ENABLED | CB_FILECLIP_NO_FILE_PATHS | CB_HUGE_FILE_SUPPORT_ENABLED;
        CLIPRDR_CAPABILITIES caps = {}; caps.cCapabilitiesSets = 1; caps.capabilitySets = reinterpret_cast<CLIPRDR_CAPABILITY_SET*>(&general);
        (void)e->clip->ClientCapabilities(e->clip, &caps);
        e->clipReady = true; e->advertise();
    });
    return CHANNEL_RC_OK;
}
static UINT clipCaps(CliprdrClientContext *clip, const CLIPRDR_CAPABILITIES *caps) {
    uint32_t flags = 0;
    const BYTE *p = reinterpret_cast<const BYTE*>(caps->capabilitySets);
    for (UINT32 n = 0; n < caps->cCapabilitiesSets; n++) {
        auto c = reinterpret_cast<const CLIPRDR_CAPABILITY_SET*>(p);
        if (c->capabilitySetLength < sizeof(CLIPRDR_CAPABILITY_SET)) break;
        if (c->capabilitySetType == CB_CAPSTYPE_GENERAL && c->capabilitySetLength >= 12) flags = reinterpret_cast<const CLIPRDR_GENERAL_CAPABILITY_SET*>(c)->generalFlags;
        p += c->capabilitySetLength;
    }
    auto e = engine(clip); e->enqueue([e, flags] { e->serverFlags = flags; });
    return CHANNEL_RC_OK;
}
static UINT clipFormats(CliprdrClientContext *clip, const CLIPRDR_FORMAT_LIST *list) {
    UINT32 files = 0, text = 0;
    for (UINT32 n = 0; n < list->numFormats; n++) {
        if (list->formats[n].formatId == CF_UNICODETEXT) text = CF_UNICODETEXT;
        if (list->formats[n].formatName && strcmp(list->formats[n].formatName, "FileGroupDescriptorW") == 0) files = list->formats[n].formatId;
    }
    auto e = engine(clip); e->enqueue([e, files, text] {
        if (!e->clip) return;
        if (e->receiving) e->finishTransfer(@"Windows 剪贴板已改变，未完成的传输已取消。");
        e->clipboardEpoch++;
        e->remoteFilesID = files; e->remoteTextID = text;
        CLIPRDR_FORMAT_LIST_RESPONSE reply = {}; reply.common.msgFlags = CB_RESPONSE_OK;
        (void)e->clip->ClientFormatListResponse(e->clip, &reply);
        e->event(@"remoteFiles", files ? @"ready" : @"");
        e->requestText();
    });
    return CHANNEL_RC_OK;
}
static UINT clipFormatAcknowledged(CliprdrClientContext *, const CLIPRDR_FORMAT_LIST_RESPONSE *) { return CHANNEL_RC_OK; }
static UINT clipDataRequest(CliprdrClientContext *clip, const CLIPRDR_FORMAT_DATA_REQUEST *request) {
    auto e = engine(clip); uint32_t format = request->requestedFormatId;
    e->enqueue([e, format] {
        if (!e->clip) return;
        CLIPRDR_FORMAT_DATA_RESPONSE reply = {}; reply.common.msgFlags = CB_RESPONSE_FAIL;
        BYTE *allocated = nullptr;
        if (format == CF_UNICODETEXT && e->localText) {
            reply.requestedFormatData = (const BYTE*)e->localText.bytes;
            reply.common.dataLen = (UINT32)e->localText.length;
            reply.common.msgFlags = CB_RESPONSE_OK;
        } else if (format == 0xC001 && !e->localFiles.empty()) {
            std::vector<FILEDESCRIPTORW> descriptors(e->localFiles.size());
            for (size_t i = 0; i < descriptors.size(); i++) {
                auto &d = descriptors[i]; auto &f = e->localFiles[i];
                d.dwFlags = FD_ATTRIBUTES | FD_FILESIZE;
                d.dwFileAttributes = f.directory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
                d.nFileSizeHigh = (UINT32)(f.size >> 32); d.nFileSizeLow = (UINT32)f.size;
                NSData *name = [str(f.name.c_str()) dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
                memcpy(d.cFileName, name.bytes, std::min<size_t>(name.length, sizeof(d.cFileName) - 2));
            }
            if (cliprdr_serialize_file_list_ex(e->serverFlags, descriptors.data(), (UINT32)descriptors.size(), &allocated, &reply.common.dataLen) == CHANNEL_RC_OK) {
                reply.requestedFormatData = allocated; reply.common.msgFlags = CB_RESPONSE_OK;
            }
        }
        (void)e->clip->ClientFormatDataResponse(e->clip, &reply); free(allocated);
    }); return CHANNEL_RC_OK;
}
static UINT clipDataResponse(CliprdrClientContext *clip, const CLIPRDR_FORMAT_DATA_RESPONSE *response) {
    auto e = engine(clip);
    if (response->common.dataLen > 32 * 1024 * 1024) return ERROR_INVALID_DATA;
    NSData *data = [NSData dataWithBytes:response->requestedFormatData length:response->common.dataLen];
    bool ok = (response->common.msgFlags & CB_RESPONSE_OK) != 0;
    e->enqueue([e, data, ok] {
        int kind = e->pendingFormat; e->pendingFormat = 0;
        if (e->pendingEpoch != e->clipboardEpoch) { e->requestText(); return; }
        if (!ok) { if (kind == 2) e->finishTransfer(@"Windows 拒绝了文件剪贴板请求。"); return; }
        if (kind == 1) {
            if (data.length % 2) return;
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
            if (text) { NSRange nul = [text rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]]; if (nul.location != NSNotFound) text = [text substringToIndex:nul.location]; [e->owner setRemoteText:text]; }
        } else if (kind == 2 && e->receiving) {
            FILEDESCRIPTORW *descriptors = nullptr; UINT32 count = 0;
            if (cliprdr_parse_file_list((const BYTE*)data.bytes, (UINT32)data.length, &descriptors, &count) != CHANNEL_RC_OK || !count || count > 10000) { free(descriptors); e->finishTransfer(@"文件列表无效或文件数量超过 10,000。"); return; }
            e->remoteFiles.clear(); e->totalBytes = 0; e->transferred = 0; e->receiveIndex = 0; e->offset = 0;
            std::set<std::string> names;
            bool valid = true;
            for (UINT32 i = 0; i < count; i++) {
                auto &d = descriptors[i]; size_t length = 0;
                while (length < 260 && d.cFileName[length]) length++;
                NSString *name = [[NSString alloc] initWithBytes:d.cFileName length:length * 2 encoding:NSUTF16LittleEndianStringEncoding];
                if (!name || length == 260 || !gravix::safeRelativePath(name.UTF8String) || !names.insert(name.lowercaseString.UTF8String).second) { valid = false; break; }
                bool directory = (d.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
                uint64_t size = ((uint64_t)d.nFileSizeHigh << 32) | d.nFileSizeLow;
                if (!directory && (!(d.dwFlags & FD_FILESIZE) || UINT64_MAX - e->totalBytes < size)) { valid = false; break; }
                e->remoteFiles.push_back({name.UTF8String, directory ? 0 : size, directory});
                if (!directory) e->totalBytes += size;
            }
            free(descriptors);
            if (!valid) { e->finishTransfer(@"文件路径或大小无效，传输已拒绝。"); return; }
            NSError *error = nil;
            e->receiveRoot = [e->receiveDestination URLByAppendingPathComponent:[@"Windows-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            if (![[NSFileManager defaultManager] createDirectoryAtURL:e->receiveRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) { e->finishTransfer(@"无法创建接收文件夹。"); return; }
            NSDictionary *space = [[NSFileManager defaultManager] attributesOfFileSystemForPath:e->receiveRoot.path error:nil];
            if (e->totalBytes > [space[NSFileSystemFreeSize] unsignedLongLongValue]) { e->finishTransfer(@"Mac 的可用磁盘空间不足。"); return; }
            e->requestChunk();
        }
    }); return CHANNEL_RC_OK;
}
static UINT clipFileRequest(CliprdrClientContext *clip, const CLIPRDR_FILE_CONTENTS_REQUEST *request) {
    auto e = engine(clip); const auto r = *request;
    e->enqueue([e, r] {
        if (!e->clip) return;
        CLIPRDR_FILE_CONTENTS_RESPONSE reply = {}; reply.streamId = r.streamId; reply.common.msgFlags = CB_RESPONSE_FAIL;
        std::vector<BYTE> bytes;
        if (r.listIndex < e->localFiles.size() && r.cbRequested <= 1024 * 1024) {
            auto &file = e->localFiles[r.listIndex];
            if (r.dwFlags == FILECONTENTS_SIZE) { bytes.resize(8); uint64_t size = file.size; memcpy(bytes.data(), &size, 8); reply.common.msgFlags = CB_RESPONSE_OK; }
            else if (r.dwFlags == FILECONTENTS_RANGE && !file.directory) {
                uint64_t position = ((uint64_t)r.nPositionHigh << 32) | r.nPositionLow;
                uint32_t count = position <= file.size ? (uint32_t)std::min<uint64_t>(r.cbRequested, file.size - position) : 0;
                if (gravix::validRange(file.size, position, count)) {
                    int fd = open(file.path.c_str(), O_RDONLY | O_NOFOLLOW);
                    struct stat s = {};
                    if (fd >= 0 && fstat(fd, &s) == 0 && S_ISREG(s.st_mode) && s.st_dev == file.device && s.st_ino == file.inode && (uint64_t)s.st_size == file.size) {
                        bytes.resize(count); ssize_t got = pread(fd, bytes.data(), count, (off_t)position);
                        if (got >= 0) { bytes.resize((size_t)got); reply.common.msgFlags = CB_RESPONSE_OK; }
                    }
                    if (fd >= 0) close(fd);
                }
            }
        }
        reply.cbRequested = (UINT32)bytes.size(); reply.requestedData = bytes.data();
        (void)e->clip->ClientFileContentsResponse(e->clip, &reply);
    }); return CHANNEL_RC_OK;
}
static UINT clipFileResponse(CliprdrClientContext *clip, const CLIPRDR_FILE_CONTENTS_RESPONSE *response) {
    if (response->cbRequested > 1024 * 1024) return ERROR_INVALID_DATA;
    auto e = engine(clip); const UINT32 stream = response->streamId;
    bool ok = (response->common.msgFlags & CB_RESPONSE_OK) != 0;
    NSData *data = [NSData dataWithBytes:response->requestedData length:response->cbRequested];
    e->enqueue([e, stream, data, ok] {
        if (!e->receiving || stream != e->expectedStream) return;
        if (!ok || data.length == 0 || data.length > e->expectedBytes || e->outputFD < 0) { e->finishTransfer(@"文件传输中断，未完成的文件已清理。"); return; }
        size_t done = 0;
        while (done < data.length) {
            ssize_t n = write(e->outputFD, (const char*)data.bytes + done, data.length - done);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) { e->finishTransfer(@"无法写入文件，请检查磁盘空间。"); return; }
            done += (size_t)n;
        }
        e->offset += done; e->transferred += done;
        double now = [NSDate timeIntervalSinceReferenceDate];
        if (now - e->progressTime > 0.15) {
            e->progressTime = now;
            e->event(@"transfer", [NSString stringWithFormat:@"正在接收 %.1f / %.1f MB", e->transferred / 1048576.0, e->totalBytes / 1048576.0]);
        }
        e->requestChunk();
    }); return CHANNEL_RC_OK;
}
static UINT displayCaps(DispClientContext *disp, UINT32, UINT32, UINT32) {
    auto e = static_cast<Engine*>(disp->custom); e->enqueue([e] { e->dispReady = true; e->resize(); }); return CHANNEL_RC_OK;
}
static void channelConnected(void *context, const ChannelConnectedEventArgs *event) {
    auto ctx = (rdpContext*)context; auto e = engine(ctx);
    if (strcmp(event->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) {
        e->clip = (CliprdrClientContext*)event->pInterface; auto clip = e->clip; clip->custom = e;
        clip->MonitorReady = clipReady; clip->ServerCapabilities = clipCaps;
        clip->ServerFormatList = clipFormats; clip->ServerFormatListResponse = clipFormatAcknowledged;
        clip->ServerFormatDataRequest = clipDataRequest; clip->ServerFormatDataResponse = clipDataResponse;
        clip->ServerFileContentsRequest = clipFileRequest; clip->ServerFileContentsResponse = clipFileResponse;
    } else if (strcmp(event->name, DISP_DVC_CHANNEL_NAME) == 0) {
        e->disp = (DispClientContext*)event->pInterface; e->disp->custom = e; e->disp->DisplayControlCaps = displayCaps;
    } else freerdp_client_OnChannelConnectedEventHandler(context, event);
}
static void channelDisconnected(void *context, const ChannelDisconnectedEventArgs *event) {
    auto ctx = (rdpContext*)context; auto e = engine(ctx);
    if (strcmp(event->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) { e->clip = nullptr; e->clipReady = false; }
    else if (strcmp(event->name, DISP_DVC_CHANNEL_NAME) == 0) { e->disp = nullptr; e->dispReady = false; }
    else freerdp_client_OnChannelDisconnectedEventHandler(context, event);
}
static BOOL beginPaint(rdpContext *ctx) { ctx->gdi->primary->hdc->hwnd->invalid->null = TRUE; return TRUE; }
static BOOL endPaint(rdpContext *ctx) {
    auto gdi = ctx->gdi; auto e = engine(ctx);
    if (gdi->primary->hdc->hwnd->invalid->null || e->stopping) return TRUE;
    { std::lock_guard<std::mutex> lock(e->frameMutex);
        e->latestFrame = [NSData dataWithBytes:gdi->primary_buffer length:(NSUInteger)gdi->stride * gdi->height];
        e->frameW = gdi->width; e->frameH = gdi->height; e->frameStride = gdi->stride;
    }
    if (!e->frameQueued.exchange(true)) {
        GRSession *session = e->owner;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSData *frame; int w, h, stride;
            { std::lock_guard<std::mutex> lock(e->frameMutex); frame = e->latestFrame; w = e->frameW; h = e->frameH; stride = e->frameStride; e->frameQueued = false; }
            if (!e->stopping) [session.desktopView showPixels:frame width:w height:h stride:stride];
        });
    }
    return TRUE;
}
static BOOL desktopResize(rdpContext *ctx) {
    UINT32 w = freerdp_settings_get_uint32(ctx->settings, FreeRDP_DesktopWidth), h = freerdp_settings_get_uint32(ctx->settings, FreeRDP_DesktopHeight);
    if (!w || !h || w > 8192 || h > 8192) return FALSE;
    return gdi_resize(ctx->gdi, w, h);
}
struct NativePointer { rdpPointer common; void *cursor; };
static BOOL pointerNew(rdpContext *, rdpPointer *pointer) {
    if (!pointer->width || !pointer->height || pointer->width > 384 || pointer->height > 384) return FALSE;
    NSMutableData *pixels = [NSMutableData dataWithLength:(NSUInteger)pointer->width * pointer->height * 4];
    if (!freerdp_image_copy_from_pointer_data((BYTE*)pixels.mutableBytes, PIXEL_FORMAT_BGRA32, pointer->width * 4, 0, 0, pointer->width, pointer->height, pointer->xorMaskData, pointer->lengthXorMask, pointer->andMaskData, pointer->lengthAndMask, pointer->xorBpp, nullptr)) return FALSE;
    __block NSCursor *cursor;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:pointer->width pixelsHigh:pointer->height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bitmapFormat:NSBitmapFormatAlphaFirst | NSBitmapFormatThirtyTwoBitLittleEndian bytesPerRow:pointer->width * 4 bitsPerPixel:32];
        memcpy(rep.bitmapData, pixels.bytes, pixels.length);
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(pointer->width, pointer->height)]; [image addRepresentation:rep];
        cursor = [[NSCursor alloc] initWithImage:image hotSpot:NSMakePoint(pointer->xPos, pointer->yPos)];
    });
    reinterpret_cast<NativePointer*>(pointer)->cursor = (__bridge_retained void*)cursor; return TRUE;
}
static void pointerFree(rdpContext *, rdpPointer *pointer) { CFBridgingRelease(reinterpret_cast<NativePointer*>(pointer)->cursor); }
static BOOL pointerSet(rdpContext *ctx, rdpPointer *pointer) {
    GRSession *session = engine(ctx)->owner; NSCursor *cursor = (__bridge NSCursor*)reinterpret_cast<NativePointer*>(pointer)->cursor;
    dispatch_async(dispatch_get_main_queue(), ^{ session.desktopView.remoteCursor = cursor; [session.desktopView.window invalidateCursorRectsForView:session.desktopView]; }); return TRUE;
}
static BOOL pointerDefault(rdpContext *ctx) {
    GRSession *session = engine(ctx)->owner; dispatch_async(dispatch_get_main_queue(), ^{ session.desktopView.remoteCursor = NSCursor.arrowCursor; [session.desktopView.window invalidateCursorRectsForView:session.desktopView]; }); return TRUE;
}
static BOOL pointerNull(rdpContext *ctx) { return pointerDefault(ctx); }
static BOOL preConnect(freerdp *instance) {
    return PubSub_SubscribeChannelConnected(instance->context->pubSub, channelConnected) >= 0 && PubSub_SubscribeChannelDisconnected(instance->context->pubSub, channelDisconnected) >= 0;
}
static BOOL postConnect(freerdp *instance) {
    if (freerdp_settings_get_uint32(instance->context->settings, FreeRDP_DesktopWidth) > 8192 || freerdp_settings_get_uint32(instance->context->settings, FreeRDP_DesktopHeight) > 8192) return FALSE;
    if (!gdi_init(instance, PIXEL_FORMAT_BGRA32)) return FALSE;
    auto ctx = instance->context; ctx->update->BeginPaint = beginPaint; ctx->update->EndPaint = endPaint; ctx->update->DesktopResize = desktopResize;
    rdpPointer pointer = {}; pointer.size = sizeof(NativePointer); pointer.New = pointerNew; pointer.Free = pointerFree; pointer.Set = pointerSet; pointer.SetNull = pointerNull; pointer.SetDefault = pointerDefault;
    graphics_register_pointer(ctx->graphics, &pointer);
    return TRUE;
}
static void postDisconnect(freerdp *instance) {
    auto ctx = instance->context;
    PubSub_UnsubscribeChannelConnected(ctx->pubSub, channelConnected); PubSub_UnsubscribeChannelDisconnected(ctx->pubSub, channelDisconnected);
    gdi_free(instance);
}
static DWORD verify(Engine *e, const char *host, UINT16 port, const char *fingerprint, const char *oldFingerprint) {
    if (e->stopping) return 0;
    __block DWORD result = 0;
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (e->stopping) return;
        NSAlert *alert = [NSAlert new]; alert.alertStyle = oldFingerprint ? NSAlertStyleCritical : NSAlertStyleWarning;
        alert.messageText = oldFingerprint ? @"远程电脑的证书已改变" : @"确认远程电脑的身份";
        alert.informativeText = [NSString stringWithFormat:@"服务器：%@:%u\n\n证书指纹：\n%@%@\n\n请与服务器管理员核对后再信任。", str(host), port, str(fingerprint), oldFingerprint ? [@"\n\n原证书指纹：\n" stringByAppendingString:str(oldFingerprint)] : @""];
        [alert addButtonWithTitle:@"取消连接"]; [alert addButtonWithTitle:@"仅本次信任"]; [alert addButtonWithTitle:@"信任并记住"];
        NSModalResponse choice = [alert runModal];
        if (choice == NSAlertSecondButtonReturn) result = 2; else if (choice == NSAlertThirdButtonReturn) result = 1;
    }); return e->stopping ? 0 : result;
}
static DWORD verifyCertificate(freerdp *instance, const char *host, UINT16 port, const char *, const char *, const char *, const char *fingerprint, DWORD) { return verify(engine(instance->context), host, port, fingerprint, nullptr); }
static DWORD verifyChanged(freerdp *instance, const char *host, UINT16 port, const char *, const char *, const char *, const char *fingerprint, const char *, const char *, const char *oldFingerprint, DWORD) { return verify(engine(instance->context), host, port, fingerprint, oldFingerprint); }
static BOOL authenticate(freerdp *, char **username, char **password, char **, rdp_auth_reason reason) {
    // Some TLS/RDSTLS paths call AuthenticateEx even with complete credentials.
    // Reuse only the values provided through our own connection form; never read stdin.
    switch (reason) {
        case AUTH_NLA: case AUTH_TLS: case AUTH_RDP: case AUTH_RDSTLS:
            return username && *username && **username && password && *password;
        default: return FALSE;
    }
}
static BOOL clientNew(freerdp *instance, rdpContext *) {
    instance->PreConnect = preConnect; instance->PostConnect = postConnect; instance->PostDisconnect = postDisconnect;
    instance->VerifyCertificateEx = verifyCertificate; instance->VerifyChangedCertificateEx = verifyChanged; instance->AuthenticateEx = authenticate;
    return TRUE;
}

@implementation GRSession
+ (NSString *)engineVersion { return [NSString stringWithFormat:@"FreeRDP %s · FFmpeg · VideoToolbox", freerdp_get_version_string()]; }
- (instancetype)initWithConfiguration:(NSDictionary *)configuration password:(NSString *)password {
    if ((self = [super init])) {
        _configuration = [configuration copy]; _password = [password copy]; _engine = new Engine(self);
        _desktopView = [[GRDesktopView alloc] initWithFrame:NSMakeRect(0, 0, 1440, 900)]; _desktopView.session = self;
        _pasteboardChange = -1;
    } return self;
}
- (void)dealloc { [_clipboardTimer invalidate]; delete _engine; }
- (void)emit:(NSString *)event detail:(NSString *)detail {
    dispatch_async(dispatch_get_main_queue(), ^{ if ([detail isEqual:@"connected"] && self->_engine->stopping) return; if (self.eventHandler) self.eventHandler(event, detail); });
}
- (void)start {
    if (_started) return; _started = YES;
    static dispatch_once_t cryptoPaths;
    dispatch_once(&cryptoPaths, ^{
        NSString *frameworks = NSBundle.mainBundle.privateFrameworksPath;
        if ([[NSFileManager defaultManager] fileExistsAtPath:[frameworks stringByAppendingPathComponent:@"legacy.dylib"]]) setenv("OPENSSL_MODULES", frameworks.fileSystemRepresentation, 1);
    });
    __weak GRSession *weak = self;
    _clipboardTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *) { [weak pollClipboard]; }];
    [self emit:@"state" detail:@"connecting"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        @autoreleasepool {
            auto e = self->_engine;
            RDP_CLIENT_ENTRY_POINTS entries = {}; entries.Version = RDP_CLIENT_INTERFACE_VERSION; entries.Size = sizeof(entries); entries.ContextSize = sizeof(GRContext); entries.ClientNew = clientNew;
            auto ctx = freerdp_client_context_new(&entries);
            if (!ctx) { [self emit:@"error" detail:@"无法初始化 RDP 引擎。"]; self->_password = nil; return; }
            reinterpret_cast<GRContext*>(ctx)->engine = e;
            { std::lock_guard<std::mutex> lock(e->lifecycle); e->ctx = ctx; }
            NSDictionary *c = self->_configuration;
            std::vector<std::string> args = { "gravix", "/bpp:32", "/network:auto", "/gfx:avc420", "/compression", "/timeout:15000", "/log-level:WARN" };
            args.push_back([c[@"hardware"] boolValue] ? "/gdi:hw" : "/gdi:sw");
            if ([c[@"clipboard"] boolValue]) args.push_back("+clipboard");
            if ([c[@"dynamic"] boolValue]) args.push_back("/dynamic-resolution");
            NSString *share = c[@"share"];
            if (share.length) args.push_back(std::string("/drive:Gravix,") + share.UTF8String);
            std::vector<char*> argv; for (auto &arg : args) argv.push_back(arg.data());
            int parsed = freerdp_client_settings_parse_command_line(ctx->settings, (int)argv.size(), argv.data(), FALSE);
            auto settings = ctx->settings;
            freerdp_settings_set_bool(settings, FreeRDP_UnicodeInput, TRUE);
            freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, FALSE);
            freerdp_settings_set_string(settings, FreeRDP_ServerHostname, [c[@"host"] UTF8String]);
            freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, [c[@"port"] unsignedIntValue]);
            freerdp_settings_set_string(settings, FreeRDP_Username, [c[@"username"] UTF8String]);
            freerdp_settings_set_string(settings, FreeRDP_Domain, [c[@"domain"] UTF8String]);
            freerdp_settings_set_string(settings, FreeRDP_Password, self->_password.UTF8String ?: "");
            self->_password = nil;
            e->dynamic = [c[@"dynamic"] boolValue];
            e->desiredW = std::clamp([c[@"width"] intValue], 200, 8192) & ~1;
            e->desiredH = std::clamp([c[@"height"] intValue], 200, 8192);
            freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, e->desiredW);
            freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, e->desiredH);
            BOOL success = parsed >= 0 && !e->stopping && freerdp_connect(ctx->instance);
            if (success && !e->stopping) {
                e->connected = true; [self emit:@"state" detail:@"connected"];
                while (!e->stopping && !freerdp_shall_disconnect_context(ctx)) {
                    @autoreleasepool {
                        e->drain();
                        if ((e->receiving || e->pendingFormat) && [NSDate timeIntervalSinceReferenceDate] - e->requestTime > 30) {
                            e->finishTransfer(@"剪贴板请求超时；通道无响应时请断开后重连。");
                            // Keep the outstanding format request until its reply arrives. RDP
                            // format replies have no request ID, so reusing the slot could mix data.
                            e->clipboardEpoch++; e->requestTime = [NSDate timeIntervalSinceReferenceDate];
                        }
                        HANDLE handles[MAXIMUM_WAIT_OBJECTS]; DWORD count = freerdp_get_event_handles(ctx, handles, MAXIMUM_WAIT_OBJECTS);
                        if (!count || WaitForMultipleObjects(count, handles, FALSE, 10) == WAIT_FAILED || !freerdp_check_event_handles(ctx)) break;
                    }
                }
            }
            e->connected = false;
            UINT32 error = freerdp_get_last_error(ctx);
            e->finishTransfer(@"连接结束，未完成的传输已取消。");
            freerdp_disconnect(ctx->instance);
            { std::lock_guard<std::mutex> lock(e->lifecycle); e->ctx = nullptr; freerdp_client_context_free(ctx); }
            e->clip = nullptr; e->disp = nullptr;
            if (!e->stopping && (!success || error)) {
                NSString *message = [NSString stringWithFormat:@"连接失败：%@（0x%08X）。请检查 Windows 远程桌面、网络及账号密码。", str(freerdp_get_last_error_name(error)), error];
                if (parsed < 0) message = @"RDP 连接参数无效。";
                [self emit:@"error" detail:message];
            } else [self emit:@"state" detail:@"disconnected"];
            dispatch_async(dispatch_get_main_queue(), ^{ [self->_clipboardTimer invalidate]; self->_clipboardTimer = nil; });
        }
    });
}
- (void)stop {
    _engine->stopping = true;
    std::lock_guard<std::mutex> lock(_engine->lifecycle);
    if (_engine->ctx) freerdp_abort_connect_context(_engine->ctx);
}
- (void)sendScan:(uint16_t)scan down:(BOOL)down {
    auto e = _engine; e->enqueue([e, scan, down] {
        if (!e->connected || !e->ctx) return;
        freerdp_input_send_keyboard_event_ex(e->ctx->input, down, FALSE, scan);
        if (down) e->heldKeys.insert(scan); else e->heldKeys.erase(scan);
    });
}
- (void)releaseKeys {
    auto e = _engine; e->enqueue([e] {
        if (e->ctx && e->connected) for (auto scan : e->heldKeys) freerdp_input_send_keyboard_event_ex(e->ctx->input, FALSE, FALSE, scan);
        e->heldKeys.clear();
    });
}
- (void)sendUnicode:(NSString *)text {
    auto e = _engine; e->enqueue([e, text] {
        if (!e->connected || !e->ctx) return;
        for (NSUInteger i = 0; i < text.length; i++) { UINT16 c = [text characterAtIndex:i]; freerdp_input_send_unicode_keyboard_event(e->ctx->input, 0, c); freerdp_input_send_unicode_keyboard_event(e->ctx->input, KBD_FLAGS_RELEASE, c); }
    });
}
- (void)sendMouse:(uint16_t)flags x:(int)x y:(int)y {
    auto e = _engine; e->enqueue([e, flags, x, y] { if (e->connected && e->ctx) freerdp_input_send_mouse_event(e->ctx->input, flags, (UINT16)x, (UINT16)y); });
}
- (void)resizeWidth:(int)width height:(int)height {
    auto e = _engine; e->enqueue([e, width, height] { e->desiredW = std::clamp(width, 200, 8192) & ~1; e->desiredH = std::clamp(height, 200, 8192); e->resize(); });
}
- (void)sendControlAltDelete {
    [self sendScan:0x1d down:YES]; [self sendScan:0x38 down:YES]; [self sendScan:0x153 down:YES];
    [self sendScan:0x153 down:NO]; [self sendScan:0x38 down:NO]; [self sendScan:0x1d down:NO];
}
- (void)receiveFilesAtURL:(NSURL *)destination { auto e = _engine; e->enqueue([e, destination] { e->startReceive(destination); }); }
- (void)cancelTransfer { auto e = _engine; e->enqueue([e] { e->finishTransfer(@"已取消接收，未完成的文件已清理。"); }); }
- (void)setRemoteText:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.desktopView.window.isKeyWindow) return;
        NSPasteboard *pb = NSPasteboard.generalPasteboard; [pb clearContents]; [pb setString:text forType:NSPasteboardTypeString]; self->_pasteboardChange = pb.changeCount;
    });
}
- (void)publishFiles:(NSArray<NSURL *> *)files {
    NSPasteboard *pb = NSPasteboard.generalPasteboard; [pb clearContents]; [pb writeObjects:files];
    _pasteboardChange = -1; [self pollClipboard];
}
- (void)pollClipboard {
    if (!_engine->connected || ![_configuration[@"clipboard"] boolValue] || !self.desktopView.window.isKeyWindow) return;
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    if (pb.changeCount == _pasteboardChange) return;
    _pasteboardChange = pb.changeCount;
    NSArray<NSURL*> *urls = [pb readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    NSString *text = [pb stringForType:NSPasteboardTypeString];
    // File enumeration and serialization stay off the UI thread.
    auto e = _engine;
    e->enqueue([e, urls, text] {
        if (e->receiving) e->finishTransfer(@"Mac 剪贴板已改变，未完成的接收已取消。");
        e->clipboardEpoch++; e->remoteFilesID = 0; e->remoteTextID = 0;
        e->event(@"remoteFiles", @"");
        e->localFiles.clear(); e->localText = nil;
        bool valid = true; std::set<std::string> names;
        for (NSURL *url in urls) {
            NSMutableArray<NSURL*> *all = [NSMutableArray arrayWithObject:url];
            NSNumber *directory; [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
            if (directory.boolValue) {
                NSDirectoryEnumerator *iter = [[NSFileManager defaultManager] enumeratorAtURL:url includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey] options:0 errorHandler:^BOOL(NSURL *, NSError *) { return NO; }];
                for (NSURL *child in iter) { [all addObject:child]; if (all.count > 10000) break; }
            }
            for (NSURL *entry in all) {
                struct stat s; if (lstat(entry.fileSystemRepresentation, &s) != 0 || (!S_ISREG(s.st_mode) && !S_ISDIR(s.st_mode))) { valid = false; break; }
                NSString *name = [entry.path substringFromIndex:url.URLByDeletingLastPathComponent.path.length + 1];
                name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"\\"];
                if (name.length >= 260 || !gravix::safeRelativePath(name.UTF8String) || !names.insert(name.lowercaseString.UTF8String).second || e->localFiles.size() >= 10000) { valid = false; break; }
                e->localFiles.push_back({entry.path.UTF8String, name.UTF8String, S_ISDIR(s.st_mode) ? 0 : (uint64_t)s.st_size, (bool)S_ISDIR(s.st_mode), s.st_dev, s.st_ino});
            }
            if (!valid) break;
        }
        if (!valid) { e->localFiles.clear(); e->event(@"transfer", @"所选文件含链接、重复名称、过长路径或超过 10,000 项，请改用共享文件夹。"); }
        else if (text && urls.count == 0 && text.length < 16 * 1024 * 1024) {
            NSMutableData *data = [[text dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy]; uint16_t nul = 0; [data appendBytes:&nul length:2]; e->localText = data;
        }
        e->advertise();
        if (!e->localFiles.empty()) e->event(@"transfer", (e->serverFlags & CB_STREAM_FILECLIP_ENABLED) ? @"文件已准备好，在 Windows 文件夹内按 ⌘V 粘贴。" : @"服务器未允许文件剪贴板；请检查 Windows 策略或改用共享文件夹。");
    });
}
@end

static uint16_t scanForKey(unsigned short key) {
    // macOS virtual key codes -> Windows set-1 scan codes; 0x100 is the extended flag.
    static const uint16_t scans[128] = {
        0x1e,0x1f,0x20,0x21,0x23,0x22,0x2c,0x2d,0x2e,0x2f,0x56,0x30,0x10,0x11,0x12,0x13,
        0x15,0x14,0x02,0x03,0x04,0x05,0x07,0x06,0x0d,0x0a,0x08,0x0c,0x09,0x0b,0x1b,0x18,
        0x16,0x1a,0x17,0x19,0x1c,0x26,0x24,0x28,0x25,0x27,0x2b,0x33,0x35,0x31,0x32,0x34,
        0x0f,0x39,0x29,0x0e,0,0x01,0x15c,0x15b,0x2a,0x3a,0x38,0x1d,0x36,0x138,0x11d,0,
        0x68,0x53,0,0x37,0,0x4e,0,0x45,0,0,0,0x135,0x11c,0,0x4a,0x69,
        0x6a,0x59,0x52,0x4f,0x50,0x51,0x4b,0x4c,0x4d,0x47,0x6b,0x48,0x49,0,0,0,
        0x3f,0x40,0x41,0x3d,0x42,0x43,0,0x57,0,0x64,0x67,0x65,0,0x44,0,0x58,
        0,0x66,0x152,0x147,0x149,0x153,0x3e,0x14f,0x3c,0x151,0x3b,0x14b,0x14d,0x150,0x148,0
    };
    return key < 128 ? scans[key] : 0;
}
@implementation GRDesktopView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES; self.layer.backgroundColor = NSColor.blackColor.CGColor;
        self.layer.contentsGravity = kCAGravityResizeAspect;
        self.marked = [NSMutableAttributedString new]; self.remoteCursor = NSCursor.arrowCursor;
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    } return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)becomeFirstResponder { self.oldModifiers = 0; [self.session pollClipboard]; return YES; }
- (BOOL)resignFirstResponder { [self.session releaseKeys]; self.oldModifiers = 0; return YES; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:self.remoteCursor ?: NSCursor.arrowCursor]; }
- (void)updateTrackingAreas {
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
    [super updateTrackingAreas];
}
- (void)showPixels:(NSData *)data width:(int)width height:(int)height stride:(int)stride {
    self.pixels = data; self.pixelWidth = width; self.pixelHeight = height;
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGImageRef image = CGImageCreate(width, height, 8, 32, stride, colors, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, provider, nullptr, false, kCGRenderingIntentDefault);
    [CATransaction begin]; [CATransaction setDisableActions:YES]; self.layer.contents = (__bridge id)image; [CATransaction commit];
    CGImageRelease(image); CGDataProviderRelease(provider); CGColorSpaceRelease(colors);
}
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self scheduleResize]; }
- (void)scheduleResize { [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendResize) object:nil]; [self performSelector:@selector(sendResize) withObject:nil afterDelay:0.3]; }
- (void)sendResize {
    double scale = [self.session->_configuration[@"retina"] boolValue] ? self.window.backingScaleFactor : 1;
    [self.session resizeWidth:(int)(self.bounds.size.width * scale) height:(int)(self.bounds.size.height * scale)];
}
- (NSPoint)remotePoint:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    double scale = std::min(self.bounds.size.width / MAX(1, self.pixelWidth), self.bounds.size.height / MAX(1, self.pixelHeight));
    if (scale <= 0) return NSZeroPoint;
    double dx = (self.bounds.size.width - self.pixelWidth * scale) / 2;
    double dy = (self.bounds.size.height - self.pixelHeight * scale) / 2;
    return NSMakePoint(std::clamp((point.x - dx) / scale, 0.0, (double)MAX(0, self.pixelWidth - 1)), std::clamp((point.y - dy) / scale, 0.0, (double)MAX(0, self.pixelHeight - 1)));
}
- (void)mouseEvent:(NSEvent *)event flags:(uint16_t)flags { NSPoint p = [self remotePoint:event]; [self.session sendMouse:flags x:p.x y:p.y]; }
- (void)mouseDown:(NSEvent *)event { [self.window makeFirstResponder:self]; [self mouseEvent:event flags:PTR_FLAGS_BUTTON1 | PTR_FLAGS_DOWN]; }
- (void)mouseUp:(NSEvent *)event { [self mouseEvent:event flags:PTR_FLAGS_BUTTON1]; }
- (void)rightMouseDown:(NSEvent *)event { [self mouseEvent:event flags:PTR_FLAGS_BUTTON2 | PTR_FLAGS_DOWN]; }
- (void)rightMouseUp:(NSEvent *)event { [self mouseEvent:event flags:PTR_FLAGS_BUTTON2]; }
- (void)otherMouseDown:(NSEvent *)event { [self mouseEvent:event flags:PTR_FLAGS_BUTTON3 | PTR_FLAGS_DOWN]; }
- (void)otherMouseUp:(NSEvent *)event { [self mouseEvent:event flags:PTR_FLAGS_BUTTON3]; }
- (void)mouseMoved:(NSEvent *)event { [self mouseEvent:event flags:PTR_FLAGS_MOVE]; }
- (void)mouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)rightMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self mouseMoved:event]; }
- (void)scrollWheel:(NSEvent *)event {
    if (event.scrollingDeltaY) { int amount = std::min(240, std::max(1, (int)(fabs(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 3 : 120)))); if (event.scrollingDeltaY < 0) amount = -amount; [self.session sendMouse:PTR_FLAGS_WHEEL | (amount & 0x1ff) x:0 y:0]; }
    if (event.scrollingDeltaX) { int amount = event.scrollingDeltaX < 0 ? -120 : 120; [self.session sendMouse:PTR_FLAGS_HWHEEL | (amount & 0x1ff) x:0 y:0]; }
}
- (void)controlShortcut:(uint16_t)scan {
    [self.session sendScan:0x1d down:YES]; [self.session sendScan:scan down:YES]; [self.session sendScan:scan down:NO]; [self.session sendScan:0x1d down:NO];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.window.firstResponder != self || !(event.modifierFlags & NSEventModifierFlagCommand)) return NO;
    if (event.keyCode == 9) { [self paste:nil]; return YES; }
    if (event.keyCode == 8) { [self copy:nil]; return YES; }
    if (event.keyCode == 7 || event.keyCode == 0 || event.keyCode == 6 || event.keyCode == 16 || event.keyCode == 1 || event.keyCode == 3) { [self controlShortcut:scanForKey(event.keyCode)]; return YES; }
    return NO;
}
- (void)copy:(id)sender { [self controlShortcut:0x2e]; }
- (void)paste:(id)sender { [self.session pollClipboard]; [self controlShortcut:0x2f]; }
- (void)cut:(id)sender { [self controlShortcut:0x2d]; }
- (void)selectAll:(id)sender { [self controlShortcut:0x1e]; }
- (void)keyDown:(NSEvent *)event {
    if (event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagCommand)) { uint16_t scan = scanForKey(event.keyCode); if (scan) [self.session sendScan:scan down:YES]; return; }
    // AppKit's input context commits Unicode and supports macOS Chinese input methods.
    if (![self.inputContext handleEvent:event]) [self doCommandBySelector:@selector(noop:)];
}
- (void)keyUp:(NSEvent *)event { uint16_t scan = scanForKey(event.keyCode); if (scan) [self.session sendScan:scan down:NO]; }
- (void)flagsChanged:(NSEvent *)event {
    const NSEventModifierFlags flags[] = {NSEventModifierFlagShift, NSEventModifierFlagControl, NSEventModifierFlagOption};
    const uint16_t scans[] = {0x2a,0x1d,0x38};
    for (int i = 0; i < 3; i++) if ((event.modifierFlags & flags[i]) != (self.oldModifiers & flags[i])) [self.session sendScan:scans[i] down:(event.modifierFlags & flags[i]) != 0];
    if ((event.modifierFlags & NSEventModifierFlagCapsLock) != (self.oldModifiers & NSEventModifierFlagCapsLock)) { [self.session sendScan:0x3a down:YES]; [self.session sendScan:0x3a down:NO]; }
    self.oldModifiers = event.modifierFlags;
}
- (void)insertText:(id)string replacementRange:(NSRange)range { NSString *text = [string isKindOfClass:NSAttributedString.class] ? [string string] : string; [self unmarkText]; [self.session sendUnicode:text]; }
- (void)doCommandBySelector:(SEL)selector {
    NSEvent *event = NSApp.currentEvent; uint16_t scan = scanForKey(event.keyCode);
    if (scan) { [self.session sendScan:scan down:YES]; [self.session sendScan:scan down:NO]; }
}
- (void)setMarkedText:(id)string selectedRange:(NSRange)selected replacementRange:(NSRange)replacement {
    self.marked = [string isKindOfClass:NSAttributedString.class] ? [string mutableCopy] : [[NSMutableAttributedString alloc] initWithString:string];
}
- (void)unmarkText { [self.marked.mutableString setString:@""]; }
- (BOOL)hasMarkedText { return self.marked.length > 0; }
- (NSRange)markedRange { return self.hasMarkedText ? NSMakeRange(0, self.marked.length) : NSMakeRange(NSNotFound, 0); }
- (NSRange)selectedRange { return NSMakeRange(self.marked.length, 0); }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actual { return nil; }
- (NSUInteger)characterIndexForPoint:(NSPoint)point { return NSNotFound; }
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actual { return [self.window convertRectToScreen:[self convertRect:NSMakeRect(self.bounds.size.width / 2, self.bounds.size.height / 2, 1, 20) toView:nil]]; }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender { return NSDragOperationCopy; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL*> *files = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    if (!files.count) return NO; [self.session publishFiles:files]; return YES;
}
@end
