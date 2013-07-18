http = require 'http'
express = require 'express'
require 'express-namespace'

{BattleServer, ConnectionServer} = require './server'

server = new BattleServer()
app = express()
httpServer = http.createServer(app)

# Configuration
app.set("views", "client")
app.use(express.bodyParser())
app.use(express.methodOverride())
app.use(app.router)
app.use(express.static(__dirname + "/public"))
app.use(require('connect-assets')(src: "client"))

# Routing
app.get '/', (req, res) ->
  {PokemonData} = require './data/bw'
  res.render 'index.jade', {PokemonData}

# API
app.namespace "/v1/api", ->
  app.get '/pokemon', (req, res) ->
    {PokemonData} = require './data/bw'
    res.json(PokemonData)

userList = []

# Start responding to websocket clients
connections = new ConnectionServer(httpServer, prefix: '/socket')

connections.addEvents
  'login': (socket, username) ->
    console.log "Received user #{username}"
    userHash = {id:  socket.id, name: username}
    userList.push(userHash)
    socket.username = username

    socket.send 'login result', socket.id, socket.username, userList
    connections.broadcast 'join chatroom', userHash

    # TODO: Take team from player.
    # TODO: Validate team.
    team = defaultTeam
    server.queuePlayer(socket, team)
    if server.queuedPlayers().length == 2
      server.beginBattles()
  
  'sendchat': (socket, message) ->
    connections.broadcast 'updatechat', socket.username, message
  
  'send move': (socket, battleId, moveName) ->
    battle = server.findBattle(battleId)
    if !battle
      @send 'error', 'ERROR: Battle does not exist'
      return

    battle.makeMove(socket, moveName)
  
  'send switch': (socket, battleId, toPokemon) ->
    # TODO: Use makeSwitch instead
    battle = server.findBattle(battleId)
    if !battle
      socket.send 'error', 'ERROR: Battle does not exist'
      return

    battle.makeSwitchByName(socket, toPokemon)
  # TODO: socket.off after disconnection
  # Dequeue player in socket off

httpServer.listen(process.env.PORT || 8000)


# TODO: Implement team builder!
defaultTeam = [
  {
    name: "Pikachu"
    moves: ["Substitute", "Thunderbolt", "Hidden Power", "Grass Knot"]
    item: "Light Ball"
  }
  {
    name: "Hitmonchan"
    moves: ["Close Combat", "Mach Punch", "Ice Punch", "ThunderPunch"]
    item: "Life Orb"
  }
  {
    name: "Charizard"
    item: "Choice Specs"
    moves: ["Fire Blast", "Air Slash", "Hidden Power", "Focus Blast"]
  }
  {
    name: "Dragonite"
    item: "Leftovers"
    moves: ["Dragon Dance", "Outrage", "Fire Punch", "ExtremeSpeed"]
  }
  {
    name: "Jigglypuff"
    item: "Leftovers"
    moves: ["Sing", "Seismic Toss", "Protect", "Wish"]
  }
  {
    name: "Haunter"
    item: "Leftovers"
    moves: ["Substitute", "Disable", "Shadow Ball", "Focus Blast"]
  }
]
