package app.shisheng.shisheng_reader

import android.content.res.AssetManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shisheng/assets")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyAsset" -> {
                        val asset = call.argument<String>("asset")!!
                        val dest = call.argument<String>("dest")!!
                        try {
                            copyAsset(asset, dest)
                            result.success(dest)
                        } catch (e: Exception) {
                            result.error("COPY_FAIL", "$asset: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shisheng/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "decodeMp3" -> {
                        val path = call.argument<String>("path")!!
                        try {
                            result.success(decodeMp3ToPcm(path))
                        } catch (e: Exception) {
                            result.error("DECODE_FAIL", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun copyAsset(asset: String, dest: String) {
        val am: AssetManager = assets
        // Flutter 资源在 APK 里带 flutter_assets/ 前缀
        val key = "flutter_assets/$asset"
        val parent = File(dest).parentFile
        if (parent != null && !parent.exists()) parent.mkdirs()
        File(dest).outputStream().buffered(1 shl 20).use { out ->
            am.open(key).use { input ->
                val buf = ByteArray(1 shl 18)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    out.write(buf, 0, n)
                }
            }
        }
    }

    /** Edge MP3 → s16le PCM（保持 24kHz 单声道），MediaCodec 软解。 */
    private fun decodeMp3ToPcm(path: String): ByteArray {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var track = -1
            var mime = ""
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (m.startsWith("audio/")) {
                    track = i
                    mime = m
                    break
                }
            }
            if (track < 0) throw IllegalStateException("no audio track")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()
            val out = ByteArrayOutputStream()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            while (!outputDone) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10000)
                    if (inIdx >= 0) {
                        val buf = codec.getInputBuffer(inIdx)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, size,
                                extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIdx = codec.dequeueOutputBuffer(info, 10000)
                if (outIdx >= 0) {
                    val buf = codec.getOutputBuffer(outIdx)!!
                    if (info.size > 0) {
                        val chunk = ByteArray(info.size)
                        buf.position(info.offset)
                        buf.get(chunk)
                        out.write(chunk)
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }
            codec.stop()
            codec.release()
            return out.toByteArray()
        } finally {
            extractor.release()
        }
    }
}
