#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#include <freerdp/codec/h264.h>
#include <freerdp/codec/color.h>
extern "C" {
#include <libavutil/hwcontext.h>
#include <libavcodec/avcodec.h>
#include <libavcodec/videotoolbox.h>
}
#include <cassert>
#include <vector>
static std::vector<uint8_t> encoded;
static void addNAL(const uint8_t *data, size_t length) { encoded.insert(encoded.end(), {0,0,0,1}); encoded.insert(encoded.end(), data, data+length); }
static void compressed(void *, void *, OSStatus status, VTEncodeInfoFlags, CMSampleBufferRef sample) {
    assert(status == noErr && sample);
    auto description = CMSampleBufferGetFormatDescription(sample);
    size_t count = 0, length = 0; const uint8_t *data = nullptr; int nalLength = 0;
    assert(CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, 0, &data, &length, &count, &nalLength) == noErr);
    for (size_t i=0;i<count;i++) { assert(CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, i, &data, &length, nullptr, nullptr) == noErr); addNAL(data,length); }
    auto block = CMSampleBufferGetDataBuffer(sample); size_t total = CMBlockBufferGetDataLength(block);
    std::vector<uint8_t> bytes(total); assert(CMBlockBufferCopyDataBytes(block,0,total,bytes.data()) == noErr);
    for (size_t offset=0;offset+4<=total;) { uint32_t length; memcpy(&length,bytes.data()+offset,4); length = ntohl(length); offset+=4; assert(length<=total-offset); addNAL(bytes.data()+offset,length); offset+=length; }
}
static AVPixelFormat hardwareFormat(AVCodecContext *, const AVPixelFormat *formats) { for (auto p=formats;*p!=AV_PIX_FMT_NONE;p++) if (*p==AV_PIX_FMT_VIDEOTOOLBOX) return *p; return AV_PIX_FMT_NONE; }
int main() {
    @autoreleasepool {
        VTCompressionSessionRef encoder = nullptr;
        NSDictionary *spec = @{(__bridge NSString*)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:@YES};
        assert(VTCompressionSessionCreate(nullptr,128,128,kCMVideoCodecType_H264,(__bridge CFDictionaryRef)spec,nullptr,nullptr,compressed,nullptr,&encoder)==noErr);
        VTSessionSetProperty(encoder,kVTCompressionPropertyKey_RealTime,kCFBooleanTrue);
        VTSessionSetProperty(encoder,kVTCompressionPropertyKey_AllowFrameReordering,kCFBooleanFalse);
        VTSessionSetProperty(encoder,kVTCompressionPropertyKey_ProfileLevel,kVTProfileLevel_H264_Baseline_AutoLevel);
        CVPixelBufferRef buffer = nullptr;
        assert(CVPixelBufferCreate(nullptr,128,128,kCVPixelFormatType_32BGRA,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey:@{}},&buffer)==kCVReturnSuccess);
        CVPixelBufferLockBaseAddress(buffer,0); memset(CVPixelBufferGetBaseAddress(buffer),0x88,CVPixelBufferGetDataSize(buffer)); CVPixelBufferUnlockBaseAddress(buffer,0);
        assert(VTCompressionSessionEncodeFrame(encoder,buffer,CMTimeMake(0,30),CMTimeMake(1,30),nullptr,nullptr,nullptr)==noErr);
        assert(VTCompressionSessionCompleteFrames(encoder,kCMTimeInvalid)==noErr); assert(!encoded.empty());
        CVPixelBufferRelease(buffer); VTCompressionSessionInvalidate(encoder); CFRelease(encoder);
        AVBufferRef *device = nullptr; assert(av_hwdevice_ctx_create(&device,AV_HWDEVICE_TYPE_VIDEOTOOLBOX,nullptr,nullptr,0)>=0);
        AVCodecContext *decoder = avcodec_alloc_context3(avcodec_find_decoder(AV_CODEC_ID_H264));
        decoder->hw_device_ctx=av_buffer_ref(device); decoder->get_format=hardwareFormat;
        assert(avcodec_open2(decoder,avcodec_find_decoder(AV_CODEC_ID_H264),nullptr)>=0);
        AVPacket *packet=av_packet_alloc(); assert(av_new_packet(packet,(int)encoded.size())>=0); memcpy(packet->data,encoded.data(),encoded.size());
        assert(avcodec_send_packet(decoder,packet)>=0);
        AVFrame *frame=av_frame_alloc(); int decoded=avcodec_receive_frame(decoder,frame);
        if (decoded==AVERROR(EAGAIN)) { avcodec_send_packet(decoder,nullptr); decoded=avcodec_receive_frame(decoder,frame); }
        assert(decoded>=0 && frame->format==AV_PIX_FMT_VIDEOTOOLBOX);
        // FFmpeg requires hardware for H.264 VideoToolbox sessions (no software VT fallback).
        puts("FFmpeg decoded an H.264 frame using a VideoToolbox hardware surface");
        av_frame_free(&frame); av_packet_free(&packet); avcodec_free_context(&decoder); av_buffer_unref(&device);
        H264_CONTEXT *rdp=h264_context_new(FALSE); assert(rdp);
        assert(h264_context_set_option(rdp,H264_CONTEXT_OPTION_HW_ACCEL,TRUE)); assert(h264_context_reset(rdp,128,128));
        std::vector<BYTE> pixels(128*128*4); RECTANGLE_16 region={0,0,128,128};
        INT32 result=avc420_decompress(rdp,encoded.data(),(UINT32)encoded.size(),pixels.data(),PIXEL_FORMAT_BGRA32,128*4,128,128,&region,1);
        assert(result>=0); assert(h264_context_get_option(rdp,H264_CONTEXT_OPTION_HW_ACCEL));
        assert(pixels[0]>100 && pixels[0]<175);
        h264_context_free(rdp);
        puts("FreeRDP AVC420 hardware decoding and BGRA output tests passed");
    }
    return 0;
}
