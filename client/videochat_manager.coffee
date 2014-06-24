module.exports = class Videochat
  constructor: (@socket) ->
    @socket.onmessage = @onMessage

    moz = !!navigator.mozGetUserMedia
    chromeVersion = !!navigator.mozGetUserMedia ? 0 : parseInt(navigator.userAgent.match( /Chrom(e|ium)\/([0-9]+)\./ )[2])


    # True if the remote user has created a peerconnection and is ready to go
    @peerReady = false

    @localVideo = $("#localVideo").get(0)
    @remoteVideo = $("#remoteVideo").get(0)

    iceServers = []

    if moz
        iceServers.push
            url: 'stun:23.21.150.121'

        iceServers.push
            url: 'stun:stun.services.mozilla.com'

    if not moz
        iceServers.push
            url: 'stun:stun.l.google.com:19302'

        iceServers.push
            url: 'stun:stun.anyfirewall.com:3478'


    if not moz and chromeVersion < 28
        iceServers.push
            url: 'turn:homeo@turn.bistri.com:80'
            credential: 'homeo'


    if not moz and chromeVersion >= 28
        iceServers.push
            url: 'turn:turn.bistri.com:80'
            credential: 'homeo'
            username: 'homeo'


        iceServers.push
            url: 'turn:turn.anyfirewall.com:443?transport=tcp'
            credential: 'webrtc'
            username: 'webrtc'

    @pcConfig =
        iceServers: iceServers

    # Request user media
    getUserMedia {video: true, audio: true}, @gotMedia, @getUserMediaError
    @started = false

    # You were the first person to join the room. This will eventually be an array of order of joining
    @initiator = true

    @descriptionSet = false

    # Holds a queued up offer if you receive one and are not ready to handle it yet
    @offerMessage = null

    # Queue up reote ice candidates you receive before you are ready to handle them
    @iceCandidates = []

    # Keeps track of how many peers have connected to you.
    @connectedPeers = 0

  # Handle a socket message received from the server. Most likely just
  # a relayed message from the other peer(s?)
  onMessage: (message) =>

    msg = JSON.parse(message.data)
    console.log("Got a message from the server: ", msg)
    switch msg.type
      # Fired when a peer joins the room (ready to get setup)
      when "ready"
        @everybodyInRoom = true
        @initiator = msg.initiator

        @maybeStart()

      # Received a remote offer. Either queue it up, and handle it later
      # - most likely when your peer connection opens, or handle it now
      when "offer"
        if @pc
          @handleOfferReceived(msg)
        else
          @offerMessage = msg

      # You received an answer to your call. You do not need to queue it
      # like the offer, because if the case happens when you need to queue it,
      # Something has gone terribly wrong...
      when "answer"
        @addRemoteDescription msg

      # Your peer has a new ICE candidate, queue it up the same way as
      # an Offer, or just handle it now
      when "candidate"
        candidate = new RTCIceCandidate
          sdpMLineIndex: msg.label
          candidate: msg.candidate

        if @pc and @descriptionSet
          console.log "Adding ice from onMessage"
          @pc.addIceCandidate candidate
        else
          @iceCandidates.push candidate

      # Called when the peer disconnects from the server.
      # **NOTE** This is not the same as a peer disconnecting from the peer connection.
      # A peer disconnecting from from the PC is handled in @pc.oniceconnectionstatechanged
      when "peerLeft"
        console.log "User has been disconnected (from server). Number of peers: #{@connectedPeers}"
        @clearQueue()

      # The other person has made a PeerConnection, and is now ready to receive a call,
      # or will call you
      when "createdPeerConnection"
        console.log "Remote peer got their stream set up"
        @peerReady = true

        # It looks like you could call someone twice (look in createPeerConnection), but
        # The cases are mutually exlusive.
        if @initiator and @pc
          @call()

      when "hangup"
        @killConnection()


  #############################
  ### Setup                 ###
  #############################

  getUserMediaError: (err) =>
    alert "There was an error starting your webcam. Is your laptop lid closed?"

  # Success Callback to navigator.getUserMedia
  gotMedia: (stream) =>
    console.log "Got local media stream"

    @localBlob = window.URL.createObjectURL stream
    @localVideo.src = @localBlob
    @localStream = stream

    @maybeStart()

  # Don't actually do anything important until you have a local stream (returned from getUserMedia), and there is someone else in the room
  maybeStart: () =>
    if @localStream and @everybodyInRoom
      @createPeerConnection()

      # Was there an offer queued up? If so handle it
      if @offerMessage
        @handleOfferReceived @offerMessage
        @offerMessage = null

      @addIceFromQueue()

  # When a user DCs, clear out the local queue. This works for right now because it is only 1 on 1 chat
  # Basically when a user disconnects, we want to make it seems as if they were never there.
  clearQueue: =>
    console.log "Clearing local queue"
    @offerMessage = null
    @iceCandidates = []

  addIceFromQueue: =>
    # Were there ice candidates queued up? If so add them
    if @iceCandidates.length > 0 and @descriptionSet and @pc

      for candidate in @iceCandidates
        console.log "Adding ice from the queue"
        @pc.addIceCandidate(candidate)
      @iceCandidates = []

  #############################
  ### Peer Connection State ###
  #############################

  createPeerConnection: =>
    @pc = new RTCPeerConnection @pcConfig
    @pc.onicecandidate = @onIceCandidate # You received a new ice candidate
    @pc.onaddstream = @onRemoteStreamAdded
    @pc.onremovestream = @onRemoteStreamRemoved

    @pc.oniceconnectionstatechange = @onIceChanged
    @pc.onsignalingstatechange = @onSignalStateChanged


    window.pc = @pc #debug

    # Inform your peer that your peer connection is started - you are good to go
    @socket.send JSON.stringify
      type: "createdPeerConnection"

    if @initiator and @peerReady
      @call()

  # TODO: There will likely be more cleanup here
  killConnection: =>
    @connectedPeers = 0
    @peerReady = false
    @receivedOffer = false

    @remoteVideo.src = null


  #############################
  ### Communicating         ###
  #############################

  # The person who was first to join the room will issue a call to the other peer
  call: =>
    console.log "Sending call"
    @pc.addStream @localStream
    @pc.createOffer @setLocalAndSendMessage, () -> console.log "error creating desc", mandatory:
      OfferToReceiveAudio: true
      OfferToReceiveVideo: true

  # The second person who joined the room will send an answer after they receive an offer
  answer: =>
    console.log "Sending answer"
    @pc.createAnswer @setLocalAndSendMessage, () -> console.log "error creating desc", mandatory:
      OfferToReceiveAudio: true
      OfferToReceiveVideo: true

  # Your local description has been created, send it to your peer
  # This will either have type "offer" or "answer" - generated by webRTC
  # Depending if the callback was fired from @pc.createOffer or @pc.createAnswer
  setLocalAndSendMessage: (descr) =>
    @pc.setLocalDescription(descr)
    @socket.send JSON.stringify(descr)

  handleOfferReceived: (msg) =>
    @addRemoteDescription msg
    @receivedOffer = true

  addRemoteDescription: (msg) =>
    @connectedPeers++
    @pc.setRemoteDescription new RTCSessionDescription(msg), () =>
      console.log "!!! Remote description set !!!"
      @descriptionSet = true

      # If you got a call from the initiator, send your answer.
      if not @initiator and @peerReady
        @pc.addStream @localStream
        @answer()

      @addIceFromQueue()

  #############################
  ### Event Handlers        ###
  #############################

  # You got an ice candidate, send it to your peer
  onIceCandidate: (event) =>
    if event.candidate
      console.log('Got an ice candidate')
      @socket.send JSON.stringify
        type: 'candidate'
        label: event.candidate.sdpMLineIndex
        id: event.candidate.sdpMid
        candidate: event.candidate.candidate
    else
      console.log('End of candidates.')

  # Peer has sent your a remote stream
  onRemoteStreamAdded: (event) =>
    console.log "Remote stream added. There are now #{@pc.getRemoteStreams().length} streams."
    @remoteBlob = window.URL.createObjectURL event.stream
    @remoteVideo.src = @remoteBlob
    @remoteStream = event.stream

    @remoteVideo.play()

  # TODO: Should we do something here? I don't think so yet
  onRemoteStreamRemoved: (event) =>
    console.log "Remote Stream Removed."

  # The state of the iceconnection changed. This is very important. Once it is
  # 'disconnected', the call is OVER
  onIceChanged: (event) =>

    if event.srcElement?.iceConnectionState is 'disconnected'
      console.log "Ice connection disconnected: ", event.srcElement?.iceConnectionState, "Number of peers: ", @connectedPeers
      if @connectedPeers > 1
        @connectedPeers--
      else
        @killConnection()
        @createPeerConnection()

  onSignalStateChanged: (event) =>
    console.log "!!!!  Signal State Changed: ", event.srcElement?.signalingState

  destroy: =>
    @pc.close()
    @killConnection()
