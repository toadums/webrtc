## Simple webRTC client

This should provide a good starting point for working with webrtc. The interesting files are:

 * server.coffee (relays messages between peers and handles rooms)
 * client/application.coffee (setting up the connection)
 * client/videochat_manager.coffee (where everything webrtc happens)

## To run
First off, you will need node. Then you need to do the following:

 * install brunch: `npm install -g brunch`
 * and bower: `npm install -g bower`
 * `npm install && bower install && brunch watch`
