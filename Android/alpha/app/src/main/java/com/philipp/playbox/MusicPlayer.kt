package com.philipp.playbox

import android.content.Context
import android.media.MediaPlayer

class MusicPlayer private constructor(context: Context) {
    companion object {
        @Volatile
        private var instance: MusicPlayer? = null

        fun getInstance(context: Context): MusicPlayer {
            return instance ?: synchronized(this) {
                instance ?: MusicPlayer(context.applicationContext).also { instance = it }
            }
        }
    }

    private var mediaPlayer: MediaPlayer?
    var isMuted: Boolean = false

    init {
        mediaPlayer = MediaPlayer.create(context, R.raw.bg_music).apply {
            isLooping = true
            setVolume(1f, 1f)
        }
    }

    fun start() {
        mediaPlayer?.start()
    }

    fun pause() {
        mediaPlayer?.pause()
    }

    fun toggleMute() {
        isMuted = !isMuted
        val volume = if (isMuted) 0f else 1f
        mediaPlayer?.setVolume(volume, volume)
    }

    fun release() {
        mediaPlayer?.release()
        mediaPlayer = null
    }
}