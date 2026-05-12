package com.philipp.playbox

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sqrt
import kotlin.math.tanh
import kotlin.random.Random

// ── Matrix helpers ──────────────────────────────────────────────

fun matMul(A: List<List<Float>>, B: List<List<Float>>): List<List<Float>> {
    val r = A.size; val m = B.size; val c = B[0].size
    return List(r) { i ->
        List(c) { j ->
            var sum = 0f
            for (k in 0 until m) sum += A[i][k] * B[k][j]
            sum
        }
    }
}

fun relu(v: List<Float>): List<Float> = v.map { max(0f, it) }

// ── NeuralNet ──────────────────────────────────────────────────

class NeuralNet(
    val inputSize: Int,
    val hiddenSize: Int,
    val outputSize: Int
) {
    var W1: List<MutableList<Float>>
    var b1: MutableList<Float>
    var W2: List<MutableList<Float>>
    var b2: MutableList<Float>

    init {
        val scale1 = sqrt(2.0 / inputSize).toFloat()
        val scale2 = sqrt(2.0 / hiddenSize).toFloat()
        W1 = List(hiddenSize) { MutableList(inputSize) { Random.nextFloat() * 2 * scale1 - scale1 } }
        b1 = MutableList(hiddenSize) { 0f }
        W2 = List(outputSize) { MutableList(hiddenSize) { Random.nextFloat() * 2 * scale2 - scale2 } }
        b2 = MutableList(outputSize) { 0f }
    }

    fun forward(input: List<Float>): List<Float> {
        val h = W1.mapIndexed { i, row ->
            b1[i] + row.zip(input).sumOf { (w, x) -> (w * x).toDouble() }.toFloat()
        }
        val h2 = relu(h)
        return W2.mapIndexed { i, row ->
            tanh(b2[i] + row.zip(h2).sumOf { (w, x) -> (w * x).toDouble() }.toFloat())
        }
    }

    fun update(input: List<Float>, actionIndex: Int, target: Float, lr: Float) {
        val hPre = W1.mapIndexed { i, row ->
            b1[i] + row.zip(input).sumOf { (w, x) -> (w * x).toDouble() }.toFloat()
        }
        val h = relu(hPre)
        val oPre = W2.mapIndexed { i, row ->
            b2[i] + row.zip(h).sumOf { (w, x) -> (w * x).toDouble() }.toFloat()
        }
        val q = tanh(oPre[actionIndex])
        val deltaOut = (target - q) * (1 - q * q)

        for (j in W2[actionIndex].indices) {
            W2[actionIndex][j] += lr * deltaOut * h[j]
        }
        b2[actionIndex] += lr * deltaOut

        val deltaH = W1.indices.map { j ->
            (if (hPre[j] > 0) 1f else 0f) * W2[actionIndex][j] * deltaOut
        }
        for (i in W1.indices) {
            for (k in W1[i].indices) {
                W1[i][k] += lr * deltaH[i] * input[k]
            }
            b1[i] += lr * deltaH[i]
        }
    }

    fun toJson(): String = Gson().toJson(this)
}

// ── NeuralAIModel ───────────────────────────────────────────────

class NeuralAIModel(
    val gameType: GameType,
    private val prefs: SharedPreferences
) {
    var trainedEpisodes: Int
    var lastWinRate: Double
    var isTraining: Boolean = false
    val net: NeuralNet
    private val hiddenSize = 64
    private val lr = 0.005f
    private val gamma = 0.95f
    private val epsilonMin = 0.05f
    private var epsilon: Float

    init {
        val sizes = archForGame(gameType)
        net = NeuralNet(sizes.first, hiddenSize, sizes.second)
        trainedEpisodes = prefs.getInt("neural_eps_${gameType.name}", 0)
        lastWinRate = prefs.getFloat("neural_wr_${gameType.name}", 0f).toDouble()
        epsilon = max(epsilonMin, 0.9f - trainedEpisodes / 5000f)

        val saved = prefs.getString("neural_ai_${gameType.name}", null)
        if (saved != null) {
            try {
                val loaded = Gson().fromJson(saved, NeuralNet::class.java)
                net.W1 = loaded.W1
                net.b1 = loaded.b1
                net.W2 = loaded.W2
                net.b2 = loaded.b2
            } catch (_: Exception) {}
        }
    }

    fun save() {
        prefs.edit()
            .putString("neural_ai_${gameType.name}", net.toJson())
            .putInt("neural_eps_${gameType.name}", trainedEpisodes)
            .putFloat("neural_wr_${gameType.name}", lastWinRate.toFloat())
            .apply()
    }

    fun reset() {
        val sizes = archForGame(gameType)
        val newNet = NeuralNet(sizes.first, hiddenSize, sizes.second)
        net.W1 = newNet.W1; net.b1 = newNet.b1
        net.W2 = newNet.W2; net.b2 = newNet.b2
        trainedEpisodes = 0; lastWinRate = 0.0; epsilon = 0.9f
        prefs.edit()
            .remove("neural_ai_${gameType.name}")
            .remove("neural_eps_${gameType.name}")
            .remove("neural_wr_${gameType.name}")
            .apply()
    }

    fun pickAction(state: List<Float>, legalActions: List<Int>, explore: Boolean = false): Int {
        if (explore && Random.nextFloat() < epsilon) return legalActions.random()
        val q = net.forward(state)
        return legalActions.maxByOrNull { q[it] } ?: legalActions[0]
    }

    suspend fun trainAsync(episodes: Int, onProgress: (Double) -> Unit) {
        if (isTraining) return
        isTraining = true
        var localEpsilon = epsilon
        var wins = 0

        withContext(Dispatchers.Default) {
            val trainer = SelfPlayTrainer(gameType, net, gamma, lr)
            for (i in 0 until episodes) {
                val result = trainer.runEpisode(localEpsilon)
                if (result > 0) wins++
                localEpsilon = max(epsilonMin, localEpsilon - 0.0002f)
            }
        }

        val wr = wins.toDouble() / episodes
        epsilon = localEpsilon
        trainedEpisodes += episodes
        lastWinRate = wr
        isTraining = false
        save()
        onProgress(wr)
    }

    // ── Move pickers per game ────────────────────────────────

    fun pickTTTMove(board: List<Player?>, player: Player): Int {
        val state = board.map { cell ->
            when {
                cell == player -> 1f
                cell == null -> 0f
                else -> -1f
            }
        }
        val legal = board.indices.filter { board[it] == null }
        return pickAction(state, legal)
    }

    fun pickC4Move(board: List<List<Player?>>, player: Player): Int {
        val state = board.flatten().map { cell ->
            when {
                cell == player -> 1f
                cell == null -> 0f
                else -> -1f
            }
        }
        val legal = (0..6).filter { MinimaxAI.c4DropRow(board, it) != null }
        return pickAction(state, legal)
    }

    fun pickWildMove(board: List<Player?>, player: Player): Pair<Int, Player> {
        val state = board.map { cell ->
            when {
                cell == player -> 1f
                cell == null -> 0f
                else -> -1f
            }
        }
        val legalX = board.indices.filter { board[it] == null }
        val legalO = legalX.map { it + 9 }
        val legal = legalX + legalO
        val action = pickAction(state, legal)
        return if (action < 9) action to Player.X else (action - 9) to Player.O
    }

    companion object {
        fun archForGame(game: GameType): Pair<Int, Int> = when (game) {
            GameType.CLASSIC -> 9 to 9
            GameType.WILD -> 9 to 18
            GameType.CONNECT4 -> 42 to 7
            GameType.NOTAKTO -> 27 to 27
            GameType.SUPER_TTT -> 81 to 81
            GameType.CHECKERS -> 64 to 64
            else -> 9 to 9
        }
    }
}

// ── SelfPlayTrainer ────────────────────────────────────────────

class SelfPlayTrainer(
    private val gameType: GameType,
    private val net: NeuralNet,
    private val gamma: Float,
    private val lr: Float
) {
    fun runEpisode(epsilon: Float): Int = when (gameType) {
        GameType.CLASSIC, GameType.NOTAKTO, GameType.WILD -> runTTTEpisode(epsilon)
        GameType.CONNECT4 -> runC4Episode(epsilon)
        else -> runTTTEpisode(epsilon)
    }

    private fun runTTTEpisode(epsilon: Float): Int {
        val board = MutableList<Player?>(9) { null }
        var turn = Player.X
        val transitions = mutableListOf<Triple<List<Float>, Int, Player>>()

        while (true) {
            val state = encode(board, turn)
            val legal = board.indices.filter { board[it] == null }
            if (legal.isEmpty()) {
                transitions.forEach { (s, a, _) -> net.update(s, a, 0f, lr) }
                return 0
            }

            val action = if (Random.nextFloat() < epsilon) legal.random()
            else legal.maxByOrNull { net.forward(state)[it] }!!

            transitions.add(Triple(state, action, turn))
            board[action] = turn

            WinChecker.checkWinner(board)?.let { (winner, _) ->
                transitions.forEach { (s, a, p) ->
                    net.update(s, a, if (p == winner) 1f else -1f, lr)
                }
                return if (winner == Player.X) 1 else -1
            }
            turn = turn.opposite
        }
    }

    private fun runC4Episode(epsilon: Float): Int {
        val board = MutableList(6) { MutableList<Player?>(7) { null } }
        var turn = Player.X
        val transitions = mutableListOf<Triple<List<Float>, Int, Player>>()

        while (true) {
            val state = board.flatten().map { cell ->
                when {
                    cell == turn -> 1f
                    cell == null -> 0f
                    else -> -1f
                }
            }
            val legal = (0..6).filter { MinimaxAI.c4DropRow(board, it) != null }
            if (legal.isEmpty()) {
                transitions.forEach { (s, a, _) -> net.update(s, a, 0f, lr) }
                return 0
            }

            val action = if (Random.nextFloat() < epsilon) legal.random()
            else legal.maxByOrNull { net.forward(state)[it] }!!

            transitions.add(Triple(state, action, turn))
            MinimaxAI.c4DropRow(board, action)?.let { board[it][action] = turn }

            WinChecker.c4CheckWinner(board)?.let { winner ->
                transitions.forEach { (s, a, p) ->
                    net.update(s, a, if (p == winner) 1f else -1f, lr)
                }
                return if (winner == Player.X) 1 else -1
            }
            turn = turn.opposite
        }
    }

    private fun encode(board: List<Player?>, player: Player): List<Float> =
        board.map { cell ->
            when {
                cell == player -> 1f
                cell == null -> 0f
                else -> -1f
            }
        }
}

// ── NeuralAIStore ──────────────────────────────────────────────

class NeuralAIStore(private val context: Context) {
    companion object {
        @Volatile private var instance: NeuralAIStore? = null
        fun getInstance(context: Context): NeuralAIStore =
            instance ?: synchronized(this) { instance ?: NeuralAIStore(context.applicationContext).also { instance = it } }
    }

    private val models = mutableMapOf<GameType, NeuralAIModel>()
    private val prefs = context.getSharedPreferences("neural_ai", Context.MODE_PRIVATE)

    fun modelFor(game: GameType): NeuralAIModel {
        return models.getOrPut(game) { NeuralAIModel(game, prefs) }
    }
}