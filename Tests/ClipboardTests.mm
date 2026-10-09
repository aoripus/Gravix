// Protocol adapter tests: no server, user files, windows, or system clipboard needed.
#include "../Sources/RDPBridge/GravixRDP.mm"
#include <cassert>
static std::vector<BYTE> lastData;
static UINT16 lastFlags;
static CLIPRDR_FILE_CONTENTS_REQUEST lastRequest;
static UINT captureData(CliprdrClientContext *, const CLIPRDR_FORMAT_DATA_RESPONSE *r) {
    lastFlags = r->common.msgFlags;
    lastData.assign(r->requestedFormatData, r->requestedFormatData + r->common.dataLen); return 0;
}
static UINT captureFile(CliprdrClientContext *, const CLIPRDR_FILE_CONTENTS_RESPONSE *r) {
    lastFlags = r->common.msgFlags;
    lastData.assign(r->requestedData, r->requestedData + r->cbRequested); return 0;
}
static UINT captureRequest(CliprdrClientContext *, const CLIPRDR_FILE_CONTENTS_REQUEST *r) { lastRequest = *r; return 0; }
static UINT requestFormat(CliprdrClientContext *, const CLIPRDR_FORMAT_DATA_REQUEST *) { return 0; }
static void deliverDescriptors(Engine *e, CliprdrClientContext *clip, NSString *name, UINT64 size) {
    FILEDESCRIPTORW descriptor = {}; descriptor.dwFlags = FD_FILESIZE | FD_ATTRIBUTES; descriptor.dwFileAttributes = FILE_ATTRIBUTE_NORMAL;
    descriptor.nFileSizeLow = (UINT32)size; descriptor.nFileSizeHigh = (UINT32)(size >> 32);
    NSData *encoded = [name dataUsingEncoding:NSUTF16LittleEndianStringEncoding]; memcpy(descriptor.cFileName, encoded.bytes, encoded.length);
    BYTE *data = nullptr; UINT32 length = 0;
    assert(cliprdr_serialize_file_list(&descriptor, 1, &data, &length) == 0);
    CLIPRDR_FORMAT_DATA_RESPONSE response = {}; response.common.msgFlags = CB_RESPONSE_OK; response.common.dataLen = length; response.requestedFormatData = data;
    assert(clipDataResponse(clip, &response) == 0); free(data); e->drain();
}
int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        char *username = const_cast<char*>("test"), *password = const_cast<char*>("fixture"), *domain = const_cast<char*>("");
        assert(authenticate(nullptr, &username, &password, &domain, AUTH_TLS));
        assert(authenticate(nullptr, &username, &password, &domain, AUTH_NLA));
        assert(!authenticate(nullptr, nullptr, &password, &domain, AUTH_TLS));
        assert(!authenticate(nullptr, &username, &password, &domain, AUTH_SMARTCARD_PIN));
        GRSession *owner = [[GRSession alloc] initWithConfiguration:@{} password:@""];
        auto e = owner->_engine;
        CliprdrClientContext clip = {}; clip.custom = e; clip.ClientFormatDataResponse = captureData; clip.ClientFileContentsResponse = captureFile; clip.ClientFileContentsRequest = captureRequest; clip.ClientFormatDataRequest = requestFormat; e->clip = &clip; e->serverFlags = CB_STREAM_FILECLIP_ENABLED | CB_HUGE_FILE_SUPPORT_ENABLED;
        NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        assert([[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]);
        NSURL *source = [root URLByAppendingPathComponent:@"中文.txt"];
        NSData *content = [@"file-transfer-content" dataUsingEncoding:NSUTF8StringEncoding];
        assert([content writeToURL:source atomically:YES]);
        struct stat s; assert(lstat(source.fileSystemRepresentation, &s) == 0);
        e->localFiles.push_back({source.path.UTF8String, "中文.txt", (uint64_t)s.st_size, false, s.st_dev, s.st_ino});
        CLIPRDR_FORMAT_DATA_REQUEST format = {}; format.requestedFormatId = 0xC001;
        assert(clipDataRequest(&clip, &format) == 0); e->drain(); assert(lastFlags == CB_RESPONSE_OK);
        FILEDESCRIPTORW *descriptors = nullptr; UINT32 count = 0;
        assert(cliprdr_parse_file_list(lastData.data(), (UINT32)lastData.size(), &descriptors, &count) == 0); assert(count == 1); assert(descriptors[0].nFileSizeLow == content.length); free(descriptors);
        CLIPRDR_FILE_CONTENTS_REQUEST request = {}; request.listIndex = 0; request.dwFlags = FILECONTENTS_RANGE; request.cbRequested = 4; request.nPositionLow = 5;
        assert(clipFileRequest(&clip, &request) == 0); e->drain(); assert(lastFlags == CB_RESPONSE_OK); assert(lastData.size() == 4); assert(memcmp(lastData.data(), (const char*)content.bytes+5, 4) == 0);
        request.listIndex = 99; clipFileRequest(&clip, &request); e->drain(); assert(lastFlags == CB_RESPONSE_FAIL);
        request.listIndex = 0; request.nPositionHigh = UINT32_MAX; clipFileRequest(&clip, &request); e->drain(); assert(lastFlags == CB_RESPONSE_FAIL);
        e->remoteFilesID = 123;
        e->startReceive(root); deliverDescriptors(e, &clip, @"folder\\接收.txt", content.length);
        assert(e->receiving); assert(lastRequest.cbRequested == content.length);
        NSURL *output = [e->receiveRoot URLByAppendingPathComponent:@"folder/接收.txt"];
        CLIPRDR_FILE_CONTENTS_RESPONSE response = {}; response.streamId = lastRequest.streamId; response.common.msgFlags = CB_RESPONSE_OK; response.cbRequested = (UINT32)content.length; response.requestedData = (const BYTE*)content.bytes;
        clipFileResponse(&clip, &response); e->drain(); assert(!e->receiving); assert([[NSData dataWithContentsOfURL:output] isEqual:content]);
        e->startReceive(root); deliverDescriptors(e, &clip, @"../escape.txt", 1); assert(!e->receiving);
        e->startReceive(root); deliverDescriptors(e, &clip, @"partial.bin", 1024); assert(e->receiving);
        NSURL *partial = e->receiveRoot; e->finishTransfer(@"cancelled"); assert(![[NSFileManager defaultManager] fileExistsAtPath:partial.path]);
        [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
        e->clip = nullptr;
        puts("Clipboard descriptor, Unicode filename, file-range, receive, traversal rejection, and cancellation tests passed");
    }
    return 0;
}
