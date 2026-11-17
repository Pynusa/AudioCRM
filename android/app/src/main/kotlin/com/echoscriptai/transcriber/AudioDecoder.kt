package com.echoscriptai.transcriber

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Decodes any Android-supported audio/video file (m4a, mp3, aac, ogg, opus,
 * amr, 3gp, mp4, webm, flac, wav...) to 16 kHz mono 16-bit PCM and writes it
 * as WAV chunks of [chunkSeconds]. Used for NVIDIA Riva Whisper, which only
 * accepts WAV/FLAC/OPUS mono audio.
 */
object AudioDecoder {
    private const val TARGET_RATE = 16000

    fun decodeToWavChunks(inputPath: String, outDir: File, chunkSeconds: Int): List<Map<String, Any>> {
        outDir.mkdirs()
        outDir.listFiles()?.forEach { it.delete() }

        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)
        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                trackIndex = i
                format = f
                break
            }
        }
        if (trackIndex < 0 || format == null) {
            extractor.release()
            throw IllegalArgumentException("В файле не найдена аудиодорожка")
        }
        extractor.selectTrack(trackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME)!!
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        var srcRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var pcmEncoding = 2 // ENCODING_PCM_16BIT

        val chunks = mutableListOf<Map<String, Any>>()
        val samplesPerChunk = TARGET_RATE * chunkSeconds
        var current = ByteArrayOutputStream(samplesPerChunk * 2)
        var currentSamples = 0
        var chunkIndex = 0
        var totalSamples = 0L

        // Linear resampler state
        var resamplePos = 0.0
        var prevSample = 0f

        fun flushChunk() {
            if (currentSamples == 0) return
            val f = File(outDir, "chunk_%04d.wav".format(chunkIndex))
            writeWav(f, current.toByteArray(), TARGET_RATE)
            chunks.add(
                mapOf(
                    "path" to f.absolutePath,
                    "offsetMs" to (chunkIndex.toLong() * chunkSeconds * 1000L),
                    "durationMs" to (currentSamples * 1000L / TARGET_RATE)
                )
            )
            chunkIndex++
            current = ByteArrayOutputStream(samplesPerChunk * 2)
            currentSamples = 0
        }

        fun emit(sample: Float) {
            val v = (sample.coerceIn(-1f, 1f) * 32767f).toInt()
            current.write(v and 0xFF)
            current.write((v shr 8) and 0xFF)
            currentSamples++
            totalSamples++
            if (currentSamples >= samplesPerChunk) flushChunk()
        }

        fun pushMono(sample: Float) {
            // Resample srcRate → TARGET_RATE by linear interpolation.
            val step = srcRate.toDouble() / TARGET_RATE
            while (resamplePos <= 1.0) {
                val t = resamplePos.toFloat()
                emit(prevSample + (sample - prevSample) * t)
                resamplePos += step
            }
            resamplePos -= 1.0
            prevSample = sample
        }

        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        val timeoutUs = 10_000L
        while (!outputDone) {
            if (!inputDone) {
                val inIdx = codec.dequeueInputBuffer(timeoutUs)
                if (inIdx >= 0) {
                    val buf = codec.getInputBuffer(inIdx)!!
                    val size = extractor.readSampleData(buf, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val outIdx = codec.dequeueOutputBuffer(info, timeoutUs)
            when {
                outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val nf = codec.outputFormat
                    srcRate = nf.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = nf.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (nf.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        pcmEncoding = nf.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    }
                }
                outIdx >= 0 -> {
                    val out: ByteBuffer = codec.getOutputBuffer(outIdx)!!
                    out.position(info.offset)
                    out.limit(info.offset + info.size)
                    out.order(ByteOrder.LITTLE_ENDIAN)
                    if (pcmEncoding == 4) { // ENCODING_PCM_FLOAT
                        val fb = out.asFloatBuffer()
                        while (fb.remaining() >= channels) {
                            var sum = 0f
                            for (c in 0 until channels) sum += fb.get()
                            pushMono(sum / channels)
                        }
                    } else {
                        val sb = out.asShortBuffer()
                        while (sb.remaining() >= channels) {
                            var sum = 0f
                            for (c in 0 until channels) sum += sb.get() / 32768f
                            pushMono(sum / channels)
                        }
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
        }
        flushChunk()
        codec.stop()
        codec.release()
        extractor.release()
        if (totalSamples == 0L) throw IllegalStateException("Не удалось декодировать аудио")
        return chunks
    }

    private fun writeWav(file: File, pcm: ByteArray, rate: Int) {
        FileOutputStream(file).use { os ->
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray())
            header.putInt(36 + pcm.size)
            header.put("WAVE".toByteArray())
            header.put("fmt ".toByteArray())
            header.putInt(16)
            header.putShort(1) // PCM
            header.putShort(1) // mono
            header.putInt(rate)
            header.putInt(rate * 2)
            header.putShort(2)
            header.putShort(16)
            header.put("data".toByteArray())
            header.putInt(pcm.size)
            os.write(header.array())
            os.write(pcm)
        }
    }

    @Suppress("unused")
    private fun patchSizes(file: File) {
        RandomAccessFile(file, "rw").use { raf ->
            val len = raf.length()
            raf.seek(4); raf.write(intLE((len - 8).toInt()))
            raf.seek(40); raf.write(intLE((len - 44).toInt()))
        }
    }

    private fun intLE(v: Int) = byteArrayOf(
        (v and 0xFF).toByte(), ((v shr 8) and 0xFF).toByte(),
        ((v shr 16) and 0xFF).toByte(), ((v shr 24) and 0xFF).toByte()
    )
}
