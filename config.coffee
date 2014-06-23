exports.config =
  paths:
    watched: ["client", "vendor", "server.coffee"]

  files:
    javascripts:
      defaultExtension: "coffee"
      joinTo:
        'application.js': /^(client)/
        'vendor.js': /^(bower_components|vendor)/

    stylesheets:
      defaultExtension: 'scss'
      joinTo:
        'app.css': /^client\/styles\/app.scss/
        'vendor.css': /^bower_components/

  # Activate the brunch plugins
  plugins:
    sass:
      debug: 'comments'

  server:
    path: 'server.coffee'
    port: 3333
    run:  true
  modules:
    nameCleaner: (path) ->
      path
        # Strip the client/ prefix from module names
        .replace(/^client\//, '')
