express = require 'express'
WebSocketServer = require("ws").Server
http = require 'http'
_ = require 'underscore'
uuid = require 'node-uuid'

class User
  constructor: (@delegate, @socket) ->
    {
      @joinRoom
      @broadcast
    } = @delegate

    @id = uuid.v1()

    @socket.on "message", @onMessage

  onMessage: (message) =>

    msg = JSON.parse message

    if msg.type is 'join'
      @join msg.room

    else
      @broadcast message, @

  join: (roomId) =>
    @roomId = roomId
    @joinRoom @

class Server
  constructor: ->

    app = express()
    app.use express.static("public")

    server = http.createServer app
    server.listen 3333

    @rooms = {}

    @wss = new WebSocketServer server: server

    console.log "Server started"

    @wss.on "connection", @onOpen

  onOpen: (socket) =>
    console.log "New client connected"

    user = new User @, socket
    socket.on 'close', () =>

      if (roomId = user.roomId)
        @rooms[roomId].splice @rooms[roomId].indexOf(user), 1

        if @rooms[roomId].length is 0
          delete @rooms[roomId]

  joinRoom: (client) =>
    room = (@rooms[client.roomId] ?= [])
    if room.length isnt 2
      room.push client

    if room.length is 2
      first = true
      for client in room
        socket = client.socket
        msg = JSON.stringify
          type: "ready"
          initiator: first
        first = false
        socket.send msg

  broadcast: (message, client) =>
    room = @rooms[client.roomId]
    return if room.length < 2
    if room[0].id is client.id
      room[1].socket.send message
    else
      room[0].socket.send message

exports.startServer = (port, path, callback) ->
  new Server()
