pty = require 'pty.js'
path = require 'path'
fs = require 'fs'
_ = require 'underscore'
child = require 'child_process'

systemLanguage = do ->
  language = "en_US.UTF-8"
  if process.platform is 'darwin'
    try
      command = 'plutil -convert json -o - ~/Library/Preferences/.GlobalPreferences.plist'
      language = "#{JSON.parse(child.execSync(command).toString()).AppleLocale}.UTF-8"
  return language

filteredEnvironment = do ->
  env = _.omit process.env, 'ATOM_HOME', 'ELECTRON_RUN_AS_NODE', 'GOOGLE_API_KEY', 'NODE_ENV', 'NODE_PATH', 'userAgent', 'taskPath'
  env.LANG ?= systemLanguage
  env.TERM_PROGRAM = 'platformio-ide-terminal'
  return env

module.exports = (pwd, shell, args, options={}) ->
  callback = @async()

  if /zsh|bash/.test(shell) and args.indexOf('--login') == -1 and process.platform isnt 'win32'
    args.unshift '--login'

  if shell
    ptyProcess = pty.fork shell, args,
      cwd: pwd,
      env: filteredEnvironment,
      name: 'xterm-256color'

    title = shell = path.basename shell

    emitTitle = _.throttle ->
      emit('platformio-ide-terminal:title', ptyProcess.process)
    , 500, true

    ptyProcess.on 'data', (data) ->
      emit('platformio-ide-terminal:data', data)
      emitTitle()

    ptyProcess.on 'exit', ->
      emit('platformio-ide-terminal:exit')
      callback()

    process.on 'message', ({event, cols, rows, text}={}) ->
      console.log('received event')
      switch event
        when 'resize' then ptyProcess.resize(cols, rows)
        when 'input' then ptyProcess.master.write(text)
  else
    ptyProcess = pty.open()
    shell = ''

    title = shell = path.basename shell

    emitTitle = _.throttle ->
      emit('platformio-ide-terminal:title', ptyProcess.process)
    , 500, true

    # TODO: since this is run in a task (seperate thread?), i think that the task is not executed (aka no pty exists yet) when gdb needs the pty in order to start, need some way to wait for pty to exist (or timeout)
    # Currently able to send the task a message, then the task will emit the pty event
    console.log("found pty (in process.coffee): ", ptyProcess.pty)

    ptyProcess.slave.on 'data', (data) ->
      console.log("ptyProcess.slave data ", data)
      emit('platformio-ide-terminal:data', data)
      emitTitle()

    ptyProcess.master.on 'data', (data) ->
      console.log("ptyProcess.master data ", data)
      emit('platformio-ide-terminal:data', data)
      emitTitle()

    ptyProcess.slave.on 'exit', ->
      console.log("ptyProcess.slave exit")
      emit('platformio-ide-terminal:exit')
      callback()

    ptyProcess.master.on 'exit', ->
      console.log("ptyProcess.master exit")
      emit('platformio-ide-terminal:exit')
      callback()

    process.on 'message', ({event, cols, rows, text}={}) ->
      switch event
        when 'resize' then ptyProcess.resize(cols, rows)
        when 'input' then ptyProcess.write(text)
        when 'pty' then emit('platformio-ide-terminal:pty', ptyProcess.pty)
