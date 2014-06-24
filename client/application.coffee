Videochat = require 'videochat_manager'

module.exports = class Application
  @init: ->
    ctor = if window['MozWebSocket'] then MozWebSocket else WebSocket
    url = window.location.origin.replace 'http', 'ws'
    socket = new ctor(url, "dashcube-user")
    socket.onopen = () ->

      query = location.search.substr(1)
      result = {}
      query.split("&").forEach (part) ->
        item = part.split("=")
        result[item[0]] = decodeURIComponent(item[1])

      room = result.room

      room ?= "local" if window.location.hostname is 'localhost'

      if (room)
        socket.send JSON.stringify
          type: "join"
          room: room

      vc = new Videochat socket

      $("#hangup").on "click", () ->
        socket.send JSON.stringify
          type: "hangup"

        vc.destroy()
