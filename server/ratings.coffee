db = require './database'
@algorithm = require('./glicko2')

RATINGS_KEY = "ratings"
GLICKO2_TAU = .2

@results =
  WIN  : 1
  DRAW : 0.5  # In earlier generations, it's possible to draw.
  LOSE : 0

INVERSE_RESULTS =
  '1'   : "WIN"
  '0.5' : "DRAW"
  '0'   : "LOSE"

parsePlayer = (p) ->
  if p then JSON.parse(p) else exports.algorithm.createPlayer()

@getPlayer = (id, next) ->
  db.hget RATINGS_KEY, id, (err, json) ->
    return next(err)  if err
    return next(null, parsePlayer(json))

@getPlayers = (idArray, next) ->
  db.hmget RATINGS_KEY, idArray, (err, players) ->
    return next(err)  if err
    players = (parsePlayer(p)  for p in players)
    return next(null, players)

@getRatings = (idArray, next) ->
  exports.getPlayers idArray, (err, players) ->
    return next(err)  if err
    return next(null, players.map((p) -> p.rating))

@updatePlayers = (id, opponentId, score, next) ->
  if score not of INVERSE_RESULTS
    return next(new Error("Invalid match result: #{score}"))

  exports.getPlayer id, (err, player) ->
    return next(err)  if err
    exports.getPlayer opponentId, (err, opponent) ->
      return next(err)  if err
      winnerMatches = [{opponent, score}]
      loserMatches = [{opponent: player, score: 1.0 - score}]
      newWinner = exports.algorithm.calculate(player, winnerMatches, systemConstant: GLICKO2_TAU)
      newLoser = exports.algorithm.calculate(opponent, loserMatches, systemConstant: GLICKO2_TAU)
      db.hset(RATINGS_KEY, id, JSON.stringify(newWinner))
      db.hset(RATINGS_KEY, opponentId, JSON.stringify(newLoser))
      return next(null, [ newWinner, newLoser ])