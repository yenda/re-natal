# Re-Natal
# Bootstrap ClojureScript React Native apps
# Dan Motzenbecker
# http://oxism.com
# MIT License

fs      = require 'fs-extra'
klawSync = require 'klaw-sync'
fpath   = require 'path'
net     = require 'net'
http    = require 'http'
os      = require 'os'
child   = require 'child_process'
cli     = require 'commander'
chalk   = require 'chalk'
semver  = require 'semver'
ckDeps  = require 'check-dependencies'
pkgJson = require __dirname + '/package.json'

nodeVersion     = pkgJson.engines.node
resources       = __dirname + '/resources'
validNameRx     = /^[A-Z][0-9A-Z]*$/i
camelRx         = /([a-z])([A-Z])/g
projNameRx      = /\$PROJECT_NAME\$/g
projNameHyphRx  = /\$PROJECT_NAME_HYPHENATED\$/g
projNameUsRx    = /\$PROJECT_NAME_UNDERSCORED\$/g
interfaceDepsRx = /\$INTERFACE_DEPS\$/g
platformRx      = /\$PLATFORM\$/g
devProfilesRx   = /#_\(\$DEV_PROFILES\$\)/g
devProfilesId   = "#_($DEV_PROFILES$)"
prodProfilesRx  = /#_\(\$PROD_PROFILES\$\)/g
prodProfilesId  = "#_($PROD_PROFILES$)"
platformCleanRx = /#_\(\$PLATFORM_CLEAN\$\)/g
platformCleanId = "#_($PLATFORM_CLEAN$)"
devHostRx       = /\$DEV_HOST\$/g
ipAddressRx     = /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/i
figwheelUrlRx   = /ws:\/\/[0-9a-zA-Z\.]*:/g
appDelegateRx   = /http:\/\/[^:]+/g
debugHostRx     = /host\s+=\s+@".*";/g
rnVersion       = '0.46.3'
rnWinVersion    = '0.46.0-rc.0'
rnPackagerPort  = 8081
process.title   = 're-natal'
interfaceConf   =
  'reagent':
    cljsDir: "cljs-reagent"
    sources:
      common:  ["handlers.cljs", "subs.cljs", "db.cljs"]
      other:   []
    deps:      ['[reagent "0.5.1" :exclusions [cljsjs/react]]'
                '[re-frame "0.6.0"]']
    shims:     ["cljsjs.react"]
    sampleCommandNs: '(in-ns \'$PROJECT_NAME_HYPHENATED$.ios.core)'
    sampleCommand: '(dispatch [:set-greeting "Hello Native World!"])'
  'reagent6':
    cljsDir: "cljs-reagent6"
    sources:
      common:  ["events.cljs", "subs.cljs", "db.cljs"]
      other:   [["reagent_dom.cljs","reagent/dom.cljs"], ["reagent_dom_server.cljs","reagent/dom/server.cljs"]]
    deps:      ['[reagent "0.7.0" :exclusions [cljsjs/react cljsjs/react-dom cljsjs/react-dom-server cljsjs/create-react-class]]'
                '[re-frame "0.9.2"]']
    shims:     ["cljsjs.react", "cljsjs.react.dom", "cljsjs.react.dom.server", "cljsjs.create-react-class"]
    sampleCommandNs: '(in-ns \'$PROJECT_NAME_HYPHENATED$.ios.core)'
    sampleCommand: '(dispatch [:set-greeting "Hello Native World!"])'
  'om-next':
    cljsDir: "cljs-om-next"
    sources:
      common:  ["state.cljs"]
      other:   [["support.cljs","re_natal/support.cljs"]]
    deps:      ['[org.omcljs/om "1.0.0-beta1" :exclusions [cljsjs/react cljsjs/react-dom]]']
    shims:     ["cljsjs.react", "cljsjs.react.dom"]
    sampleCommandNs: '(in-ns \'$PROJECT_NAME_HYPHENATED$.state)'
    sampleCommand: '(swap! app-state assoc :app/msg "Hello Native World!")'
  'rum':
    cljsDir: "cljs-rum"
    sources:
      common:  []
      other:   [["sablono_compiler.clj","sablono/compiler.clj"],["support.cljs","re_natal/support.cljs"]]
    deps:      ['[rum "0.10.8" :exclusions [cljsjs/react cljsjs/react-dom sablono]]']
    shims:     ["cljsjs.react", "cljsjs.react.dom", "sablono.core"]
    sampleCommandNs: '(in-ns \'$PROJECT_NAME_HYPHENATED$.ios.core)'
    sampleCommand: '(swap! app-state assoc :greeting "Hello Clojure in iOS and Android with Rum!")'
interfaceNames   = Object.keys interfaceConf
defaultInterface = 'reagent6'
defaultEnvRoots  =
  dev: 'env/dev'
  prod: 'env/prod'
platformMeta     =
  'ios':
    name:     "iOS"
    sources:  ["core.cljs"]
  'android':
    name:     "Android"
    sources:  ["core.cljs"]
  'windows':
    name:     "UWP"
    sources:  ["core.cljs"]
  'wpf':
    name:     "WPF"
    sources:  ["core.cljs"]
platforms = []

log = (s, color = 'green') ->
  console.log chalk[color] s


logErr = (err, color = 'red') ->
  console.error chalk[color] err
  process.exit 1


exec = (cmd, keepOutput) ->
  if keepOutput
    child.execSync cmd, stdio: 'inherit'
  else
    child.execSync cmd, stdio: ['pipe', 'pipe', 'ignore']

ensureExecutableAvailable = (executable) ->
  if os.platform() == 'win32'
    try
      exec "where #{executable}"
    catch e
      throw new Error("type: #{executable}: not found")
  else
    exec "type #{executable}"

isYarnAvailable = () ->
  try
    ensureExecutableAvailable('yarn')
    true
  catch e
    false

isSomeDepsMissing = () ->
  depState = ckDeps.sync {install: false, verbose: false}
  !depState.depsWereOk

installDeps = (opts = verbose: false, report: false) ->
  {verbose, report} = opts
  if report
    ckDeps.sync (install: false, verbose: true)
  if isYarnAvailable()
    exec 'yarn', verbose
  else
    exec 'npm i', verbose

ensureOSX = (cb) ->
  if os.platform() == 'darwin'
    cb()
  else
    logErr 'This command is only available on OSX'

readFile = (path) ->
  fs.readFileSync path, encoding: 'ascii'


edit = (path, pairs) ->
  fs.writeFileSync path, pairs.reduce (contents, [rx, replacement]) ->
    contents.replace rx, replacement
  , readFile path

toUnderscored = (s) ->
  s.replace(camelRx, '$1_$2').toLowerCase()

checkPort = (port, cb) ->
  sock = net.connect {port}, ->
    sock.end()
    http.get "http://localhost:#{port}/status", (res) ->
      data = ''
      res.on 'data', (chunk) -> data += chunk
      res.on 'end', ->
        cb data.toString() isnt 'packager-status:running'

    .on 'error', -> cb true
    .setTimeout 3000

  sock.on 'error', ->
    sock.end()
    cb false

ensureFreePort = (cb) ->
  checkPort rnPackagerPort, (inUse) ->
    if inUse
      logErr "
             Port #{rnPackagerPort} is currently in use by another process
             and is needed by the React Native packager.
             "
    cb()

ensureXcode = (cb) ->
  try
    ensureExecutableAvailable 'xcodebuild'
    cb();
  catch {message}
    if message.match /type.+xcodebuild/i
      logErr 'Xcode Command Line Tools are required'

generateConfig = (interfaceName, projName) ->
  log 'Creating Re-Natal config'
  config =
    name:   projName
    interface: interfaceName
    envRoots: defaultEnvRoots
    modules: []
    imageDirs: ["images"]
    platforms: {}

  for platform in platforms
    config.platforms[platform] =
      host: "localhost"
      modules: []

  writeConfig config
  config


writeConfig = (config) ->
  try
    fs.writeFileSync './.re-natal', JSON.stringify config, null, 2
  catch {message}
    logErr message
    logErr \
      if message.match /EACCES/i
        'Invalid write permissions for creating .re-natal config file'
      else
        message

verifyConfig = (config) ->
  if !config.platforms? || !config.modules? || !config.imageDirs? || !config.interface? || !config.envRoots?
    throw new Error 're-natal project needs to be upgraded, please run: re-natal upgrade'

  config

readConfig = (verify = true)->
  try
    config = JSON.parse readFile '.re-natal'
    if (verify)
      verifyConfig(config)
    else
      config
  catch {message}
    logErr \
      if message.match /ENOENT/i
        'No Re-Natal config was found in this directory (.re-natal)'
      else if message.match /EACCES/i
        'No read permissions for .re-natal'
      else if message.match /Unexpected/i
        '.re-natal contains malformed JSON'
      else
        message

scanImageDir = (dir) ->
  fnames = fs.readdirSync(dir)
    .map (fname) -> "#{dir}/#{fname}"
    .filter (path) -> fs.statSync(path).isFile()
    .filter (path) -> removeExcludeFiles(path)
    .map (path) -> path.replace /@2x|@3x/i, ''
    .map (path) -> path.replace new RegExp(".(#{platforms.join('|')})" + fpath.extname(path) + "$", "i"), fpath.extname(path)
    .filter (v, idx, slf) -> slf.indexOf(v) == idx

  dirs = fs.readdirSync(dir)
    .map (fname) -> "#{dir}/#{fname}"
    .filter (path) -> fs.statSync(path).isDirectory()
  fnames.concat scanImages(dirs)

removeExcludeFiles = (file) ->
    excludedFileNames = [".DS_Store"]
    res = excludedFileNames.map (ex) -> (file.indexOf ex) == -1
    true in res

scanImages = (dirs) ->
  imgs = []
  for dir in dirs
    imgs = imgs.concat(scanImageDir(dir));
  imgs

resolveAndroidDevHost = (deviceType) ->
  allowedTypes = {'real': 'localhost', 'avd': '10.0.2.2', 'genymotion': '10.0.3.2'}
  devHost = allowedTypes[deviceType]
  if (devHost?)
    log "Using '#{devHost}' for device type #{deviceType}"
    devHost
  else
    deviceTypeIsIpAddress(deviceType, Object.keys(allowedTypes))

configureDevHostForAndroidDevice = (deviceType) ->
  try
    devHost = resolveAndroidDevHost(deviceType)
    config = readConfig()
    config.platforms.android.host = devHost
    writeConfig(config)
    log "Please run: re-natal use-figwheel to take effect."
  catch {message}
    logErr message

resolveIosDevHost = (deviceType) ->
  if deviceType == 'simulator'
    log "Using 'localhost' for iOS simulator"
    'localhost'
  else if deviceType == 'real'
    en0Ip = exec('ipconfig getifaddr en0').toString().trim()
    log "Using IP of interface en0:'#{en0Ip}' for real iOS device"
    en0Ip
  else
    deviceTypeIsIpAddress(deviceType, ['simulator', 'real'])

configureDevHostForIosDevice = (deviceType) ->
  try
    devHost = resolveIosDevHost(deviceType)
    config = readConfig()
    config.platforms.ios.host = devHost
    writeConfig(config)
    log "Please run: re-natal use-figwheel to take effect."
  catch {message}
    logErr message

deviceTypeIsIpAddress = (deviceType, allowedTypes) ->
  if deviceType.match(ipAddressRx)
    log "Using development host IP: '#{deviceType}'"
    deviceType
  else
    log("Value '#{deviceType}' is not a valid IP address, still configured it as development host. Did you mean one of: [#{allowedTypes}] ?", 'yellow')
    deviceType

copyDevEnvironmentFilesForPlatform = (platform, interfaceName, projNameHyph, projName, devEnvRoot, devHost) ->
  cljsDir = interfaceConf[interfaceName].cljsDir
  fs.mkdirpSync "#{devEnvRoot}/env/#{platform}"
  mainDevPath = "#{devEnvRoot}/env/#{platform}/main.cljs"
  fs.copySync("#{resources}/#{cljsDir}/main_dev.cljs", mainDevPath)
  edit mainDevPath, [[projNameHyphRx, projNameHyph], [projNameRx, projName], [platformRx, platform], [devHostRx, devHost]]

copyDevEnvironmentFiles = (interfaceName, projNameHyph, projName, devEnvRoot, devHost) ->
  userNsPath = "#{devEnvRoot}/user.clj"
  fs.copySync("#{resources}/user.clj", userNsPath)

  for platform in platforms
    copyDevEnvironmentFilesForPlatform platform, interfaceName, projNameHyph, projName, devEnvRoot, devHost

copyProdEnvironmentFilesForPlatform = (platform, interfaceName, projNameHyph, projName, prodEnvRoot) ->
  cljsDir = interfaceConf[interfaceName].cljsDir
  fs.mkdirpSync "#{prodEnvRoot}/env/#{platform}"
  mainProdPath = "#{prodEnvRoot}/env/#{platform}/main.cljs"
  fs.copySync("#{resources}/#{cljsDir}/main_prod.cljs", mainProdPath)
  edit mainProdPath, [[projNameHyphRx, projNameHyph], [projNameRx, projName], [platformRx, platform]]

copyProdEnvironmentFiles = (interfaceName, projNameHyph, projName, prodEnvRoot) ->
  for platform in platforms
    copyProdEnvironmentFilesForPlatform platform, interfaceName, projNameHyph, projName, prodEnvRoot

copyFigwheelBridge = (projNameUs) ->
  fs.copySync("#{resources}/figwheel-bridge.js", "./figwheel-bridge.js")
  edit "figwheel-bridge.js", [[projNameUsRx, projNameUs]]

updateGitIgnore = () ->
  fs.appendFileSync(".gitignore", "\n# Generated by re-natal\n#\n")

  indexFiles = platforms.map (platform) -> "index.#{platform}.js"
  fs.appendFileSync(".gitignore", indexFiles.join("\n"))
  fs.appendFileSync(".gitignore", "\ntarget/\n")

  fs.appendFileSync(".gitignore", "\n# Figwheel\n#\nfigwheel_server.log")

patchReactNativePackager = () ->
  installDeps()
  log "Patching react-native packager to serve *.map files"
  edit "node_modules/metro-bundler/build/Server/index.js",
    [[/match.*\.map\$\/\)/m, "match(/index\\..*\\.map$/)"]]

shimCljsNamespace = (ns) ->
  filePath = "src/" + ns.replace(/\./g, "/") + ".cljs"
  filePath = filePath.replace(/-/g, "_")
  fs.mkdirpSync fpath.dirname(filePath)
  fs.writeFileSync(filePath, "(ns #{ns})")

copySrcFilesForPlatform = (platform, interfaceName, projName, projNameUs, projNameHyph) ->
  cljsDir = interfaceConf[interfaceName].cljsDir
  fs.mkdirSync "src/#{projNameUs}/#{platform}"
  fileNames = platformMeta[platform].sources
  for fileName in fileNames
    path = "src/#{projNameUs}/#{platform}/#{fileName}"
    fs.copySync("#{resources}/#{cljsDir}/#{fileName}", path)
    edit path, [[projNameHyphRx, projNameHyph], [projNameRx, projName], [platformRx, platform]]

copySrcFiles = (interfaceName, projName, projNameUs, projNameHyph) ->
  cljsDir = interfaceConf[interfaceName].cljsDir

  fileNames = interfaceConf[interfaceName].sources.common;
  for fileName in fileNames
    path = "src/#{projNameUs}/#{fileName}"
    fs.copySync("#{resources}/#{cljsDir}/#{fileName}", path)
    edit path, [[projNameHyphRx, projNameHyph], [projNameRx, projName]]

  for platform in platforms
    copySrcFilesForPlatform platform, interfaceName, projName, projNameUs, projNameHyph

  otherFiles = interfaceConf[interfaceName].sources.other;
  for cpFile in otherFiles
    from = "#{resources}/#{cljsDir}/#{cpFile[0]}"
    to = "src/#{cpFile[1]}"
    fs.copySync(from, to)

  shims = fileNames = interfaceConf[interfaceName].shims;
  for namespace in shims
    shimCljsNamespace(namespace)

copyProjectClj = (interfaceName, projNameHyph) ->
  fs.copySync("#{resources}/project.clj", "project.clj")
  deps = interfaceConf[interfaceName].deps.join("\n")

  cleans = platforms.map (platform) -> "\"index.#{platform}.js\""
  cleans.push platformCleanId

  devProfileTemplate = readFile "#{resources}/dev.profile"
  devProfiles = platforms.map (platform) -> devProfileTemplate.replace(platformRx, platform)
  devProfiles.push devProfilesId

  prodProfileTemplate = readFile "#{resources}/prod.profile"
  prodProfiles = platforms.map (platform) -> prodProfileTemplate.replace(platformRx, platform)
  prodProfiles.push prodProfilesId

  edit 'project.clj', [[projNameHyphRx, projNameHyph], [interfaceDepsRx, deps], [platformCleanRx, cleans.join(' ')], [devProfilesRx, devProfiles.join("\n")], [prodProfilesRx, prodProfiles.join("\n")]]

updateProjectClj = (platform) ->
  proj = readFile('project.clj')

  cleans = []
  cleans.push "\"index.#{platform}.js\""
  cleans.push platformCleanId

  if !proj.match(platformCleanRx)
    log "Manual update of project.clj required: add clean targets:"
    log "#{cleans.join(' ')}", "red"

  devProfileTemplate = readFile "#{resources}/dev.profile"
  devProfiles = []
  devProfiles.push devProfileTemplate.replace(platformRx, platform)
  devProfiles.push devProfilesId

  if !proj.match(devProfilesRx)
    log "Manual update of project.clj required: add new build to dev profile:"
    log "#{devProfiles.join('\n')}", "red"

  prodProfileTemplate = readFile "#{resources}/prod.profile"
  prodProfiles = []
  prodProfiles.push prodProfileTemplate.replace(platformRx, platform)
  prodProfiles.push prodProfilesId

  if !proj.match(prodProfilesRx)
    log "Manual update of project.clj required: add new build to prod profile:"
    log "#{prodProfiles.join('\n')}", "red"

  edit 'project.clj', [[platformCleanRx, cleans.join(' ')], [devProfilesRx, devProfiles.join("\n")], [prodProfilesRx, prodProfiles.join("\n")]]

init = (interfaceName, projName) ->
  if projName.toLowerCase() is 'react' or !projName.match validNameRx
    logErr 'Invalid project name. Use an alphanumeric CamelCase name.'

  projNameHyph = projName.replace(camelRx, '$1-$2').toLowerCase()
  projNameUs   = toUnderscored projName

  try
    log "Creating #{projName}", 'bgMagenta'
    if isYarnAvailable()
      log '\u2615  Grab a coffee! I will use yarn, but fetching deps still takes time...', 'yellow'
    else
      log '\u2615  Grab a coffee! Downloading deps might take a while...', 'yellow'

    if fs.existsSync projNameHyph
      throw new Error "Directory #{projNameHyph} already exists"

    ensureExecutableAvailable 'lein'

    log 'Creating Leiningen project'
    exec "lein new #{projNameHyph}"

    log 'Updating Leiningen project'
    process.chdir projNameHyph
    fs.removeSync "resources"
    corePath = "src/#{projNameUs}/core.clj"
    fs.unlinkSync corePath

    copyProjectClj(interfaceName, projNameHyph)

    copySrcFiles(interfaceName, projName, projNameUs, projNameHyph)

    copyDevEnvironmentFiles(interfaceName, projNameHyph, projName, defaultEnvRoots.dev, "localhost")
    copyProdEnvironmentFiles(interfaceName, projNameHyph, projName, defaultEnvRoots.prod)

    fs.copySync("#{resources}/images", "./images")

    log 'Creating React Native skeleton.'

    pkg =
      name:    projName
      version: '0.0.1'
      private: true
      scripts:
        start: 'node node_modules/react-native/local-cli/cli.js start'
      dependencies:
        'react-native': rnVersion
        # Fixes issue with packager 'TimeoutError: transforming ... took longer than 301 seconds.'
        'babel-plugin-transform-es2015-block-scoping': '6.15.0'

    if 'windows' in platforms || 'wpf' in platforms
      pkg.dependencies['react-native-windows'] = rnWinVersion

    fs.writeFileSync 'package.json', JSON.stringify pkg, null, 2

    installDeps()

    fs.unlinkSync '.gitignore'
    exec "node -e
           \"require('react-native/local-cli/cli').init('.', '#{projName}')\"
           "

    if 'windows' in platforms
      log 'Creating React Native UWP project.'
      exec "node -e
             \"require('react-native-windows/local-cli/generate-windows')('.', '#{projName}', '#{projName}')\"
             "

    if 'wpf' in platforms
      log 'Creating React Native WPF project.'
      exec "node -e
             \"require('react-native-windows/local-cli/generate-wpf')('.', '#{projName}', '#{projName}')\"
             "

    updateGitIgnore()

    generateConfig(interfaceName, projName)

    copyFigwheelBridge(projNameUs)

    log 'Compiling ClojureScript'
    exec 'lein prod-build'

    log ''
    log 'To get started with your new app, first cd into its directory:', 'yellow'
    log "cd #{projNameHyph}", 'inverse'
    log ''
    log 'Run iOS app:' , 'yellow'
    log 'react-native run-ios > /dev/null', 'inverse'
    log ''
    log 'To use figwheel type:' , 'yellow'
    log 're-natal use-figwheel', 'inverse'
    log 'lein figwheel ios', 'inverse'
    log ''
    log 'Reload the app in simulator (\u2318 + R)'
    log ''
    log 'At the REPL prompt type this:', 'yellow'
    log interfaceConf[interfaceName].sampleCommandNs.replace(projNameHyphRx, projNameHyph), 'inverse'
    log ''
    log 'Changes you make via the REPL or by changing your .cljs files should appear live.', 'yellow'
    log ''
    log 'Try this command as an example:', 'yellow'
    log interfaceConf[interfaceName].sampleCommand, 'inverse'
    log ''
    log '✔ Done', 'bgMagenta'
    log ''

  catch {message}
    logErr \
      if message.match /type.+lein/i
        'Leiningen is required (http://leiningen.org)'
      else if message.match /npm/i
        "npm install failed. This may be a network issue. Check #{projNameHyph}/npm-debug.log for details."
      else
        message

addPlatform = (platform) ->
  try
    if !(platform of platformMeta)
      throw new Error "Unknown platform [#{platform}]"

    config = readConfig()
    platforms = Object.keys config.platforms

    if platform in platforms
      throw new Error "A project for a #{platformMeta[platform].name} app already exists"
    else
      interfaceName = config.interface
      projName      = config.name
      projNameHyph  = projName.replace(camelRx, '$1-$2').toLowerCase()
      projNameUs    = toUnderscored projName

      log "Preparing for #{platformMeta[platform].name} app."

      updateProjectClj(platform)
      copySrcFilesForPlatform(platform, interfaceName, projName, projNameUs, projNameHyph)
      copyDevEnvironmentFilesForPlatform(platform, interfaceName, projNameHyph, projName, defaultEnvRoots.dev, "localhost")
      copyProdEnvironmentFilesForPlatform(platform, interfaceName, projNameHyph, projName, defaultEnvRoots.prod)

      pkg = JSON.parse readFile 'package.json'

      unless 'react-native-windows' in pkg.dependencies
        pkg.dependencies['react-native-windows'] = rnWinVersion
        fs.writeFileSync 'package.json', JSON.stringify pkg, null, 2
        installDeps()

      if platform is 'windows'
        log 'Creating React Native UWP project.'
        exec "node -e
               \"require('react-native-windows/local-cli/generate-windows')('.', '#{projName}', '#{projName}')\"
               "

      if platform is 'wpf'
        log 'Creating React Native WPF project.'
        exec "node -e
               \"require('react-native-windows/local-cli/generate-wpf')('.', '#{projName}', '#{projName}')\"
               "

      fs.appendFileSync(".gitignore", "\n\nindex.#{platform}.js\n")

      config.platforms[platform] =
        host: "localhost"
        modules: []

      writeConfig(config)

      log 'Compiling ClojureScript'
      exec 'lein prod-build'
  catch {message}
    logErr message

openXcode = (name) ->
  try
    exec "open ios/#{name}.xcodeproj"
  catch {message}
    logErr \
      if message.match /ENOENT/i
        """
        Cannot find #{name}.xcodeproj in ios.
        Run this command from your project's root directory.
        """
      else if message.match /EACCES/i
        "Invalid permissions for opening #{name}.xcodeproj in ios"
      else
        message

generateRequireModulesCode = (modules) ->
  jsCode = "var modules={'react-native': require('react-native'), 'react': require('react'), 'create-react-class': require('create-react-class')};"
  for m in modules
    jsCode += "modules['#{m}']=require('#{m}');";
  jsCode += '\n'

updateFigwheelUrls = (devEnvRoot, devHost) ->
  for platform in platforms
    mainDevPath = "#{devEnvRoot}/env/#{platform}/main.cljs"
    edit mainDevPath, [[figwheelUrlRx, "ws://#{devHost[platform]}:"]]

# Current RN version (0.29.2) has no host in AppDelegate.m maybe docs are outdated?
updateIosAppDelegate = (projName, iosHost) ->
  appDelegatePath = "ios/#{projName}/AppDelegate.m"
  edit appDelegatePath, [[appDelegateRx, "http://#{iosHost}"]]

updateIosRCTWebSocketExecutor = (iosHost) ->
  RCTWebSocketExecutorPath = "node_modules/react-native/Libraries/WebSocket/RCTWebSocketExecutor.m"
  edit RCTWebSocketExecutorPath, [[debugHostRx, "host = @\"#{iosHost}\";"]]

platformModulesAndImages = (config, platform) ->
  images = scanImages(config.imageDirs).map (fname) -> './' + fname;
  modulesAndImages = config.modules.concat images;
  if typeof config.platforms[platform].modules is 'undefined'
    modulesAndImages
  else
    modulesAndImages.concat(config.platforms[platform].modules)

generateDevScripts = () ->
  try
    config = readConfig()
    platforms = Object.keys config.platforms
    projName = config.name
    devEnvRoot = config.envRoots.dev

    if isSomeDepsMissing()
      installDeps(verbose: true)

    log 'Cleaning...'
    exec 'lein clean'

    devHost = {}
    for platform in platforms
      devHost[platform] = config.platforms[platform].host

    for platform in platforms
      moduleMap = generateRequireModulesCode(platformModulesAndImages(config, platform))
      fs.writeFileSync "index.#{platform}.js", "#{moduleMap}require('figwheel-bridge').withModules(modules).start('#{projName}','#{platform}','#{devHost[platform]}');"
      log "index.#{platform}.js was regenerated"

    #updateIosAppDelegate(projName, devHost.ios)
    updateIosRCTWebSocketExecutor(devHost.ios)
    log "Host in RCTWebSocketExecutor.m was updated"

    updateFigwheelUrls(devEnvRoot, devHost)
    for platform in platforms
      log "Dev server host for #{platformMeta[platform].name}: #{devHost[platform]}"

  catch {message}
    logErr \
      if message.match /EACCES/i
        'Invalid write permissions for creating development scripts'
      else
        message

doUpgrade = (config) ->
  projName = config.name
  projNameHyph = projName.replace(camelRx, '$1-$2').toLowerCase()
  projNameUs   = toUnderscored projName

  unless config.interface
    config.interface = defaultInterface

  unless config.modules
    config.modules = []

  unless config.imageDirs
    config.imageDirs = ["images"]

  unless config.envRoots
    config.envRoots = defaultEnvRoots

  unless config.platforms
    config.platforms =
      ios:
        host: "localhost"
        modules: []
      android:
        host: "localhost"
        modules: []

  if config.iosHost?
    config.platforms.ios.host = config.iosHost
    delete config.iosHost

  if config.androidHost?
    config.platforms.android.host = config.androidHost
    delete config.androidHost

  if config.modulesPlatform?
    if config.modulesPlatform.ios?
      config.platforms.ios.modules = config.platforms.ios.modules.concat(config.modulesPlatform.ios)

    if config.modulesPlatform.android?
      config.platforms.android.modules = config.platforms.android.modules.concat(config.modulesPlatform.android)

    delete config.modulesPlatform

  writeConfig(config)
  log 'upgraded .re-natal'

  interfaceName = config.interface
  envRoots = config.envRoots

  copyDevEnvironmentFiles(interfaceName, projNameHyph, projName, envRoots.dev, "localhost")
  copyProdEnvironmentFiles(interfaceName, projNameHyph, projName, envRoots.prod)
  log "upgraded files in #{envRoots.dev} and #{envRoots.prod} "

  copyFigwheelBridge(projNameUs)
  log 'upgraded figwheel-bridge.js'
  log('To upgrade React Native version please follow the official guide in https://facebook.github.io/react-native/docs/upgrading.html', 'yellow')

useComponent = (name, platform) ->
  try
    config = readConfig()
    platforms = Object.keys config.platforms
    if typeof platform isnt 'string'
      config.modules.push name
      log "Component '#{name}' is now configured for figwheel, please re-run 'use-figwheel' command to take effect"
    else if platforms.indexOf(platform) > -1
      if typeof config.platforms[platform].modules is 'undefined'
        config.platforms[platform].modules = []
      config.platforms[platform].modules.push name
      log "Component '#{name}' (#{platform}-only) is now configured for figwheel, please re-run 'use-figwheel' command to take effect"
    else
      throw new Error("unsupported platform: #{platform}")
    writeConfig(config)
  catch {message}
    logErr message

inferComponents = () ->
  onlyUserCljs = (item) -> fpath.extname(item.path) == '.cljs' and
                           item.path.indexOf('/target/') < 0 # ignore target dir
  jsRequire = /js\/require \"(.+)\"/g
  files = klawSync process.cwd(),
    nodir: true
    filter: onlyUserCljs
  filenames = files.map((o) -> o.path)
  contents = filenames.map((path) -> fs.readFileSync(path, encoding: 'utf8'))

  config = readConfig() # re-natal file
  requires = new Set()
  contents.forEach((text) ->
    while match = jsRequire.exec(text)
      requires.add(match[1]) if match[1].indexOf(config.imageDirs) < 0)

  modules = new Set(config.modules)
  difference = new Set(Array.from(requires).filter((m) -> !modules.has(m)))
  if(difference.size isnt 0)
    log "new component import found #{Array.from(difference)}"
    config.modules = Array.from(requires)
    writeConfig(config)
  else
    log "no new component was imported, defaulting to #{Array.from(modules)}"

cli._name = 're-natal'
cli.version pkgJson.version

cli.command 'init <name>'
  .description 'create a new ClojureScript React Native project'
  .option "-i, --interface [#{interfaceNames.join ' '}]", 'specify React interface', defaultInterface
  .option '-u, --uwp', 'create project for UWP app'
  .option '-w, --wpf', 'create project for WPF app'
  .action (name, cmd) ->
    if typeof name isnt 'string'
      logErr '''
             re-natal init requires a project name as the first argument.
             e.g.
             re-natal init HelloWorld
             '''
    unless interfaceConf[cmd.interface]
      logErr "Unsupported React interface: #{cmd.interface}, one of [#{interfaceNames}] was expected."
    platforms.push 'ios'
    platforms.push 'android'
    if cmd.uwp?
      platforms.push 'windows'
    if cmd.wpf?
      platforms.push 'wpf'
    ensureFreePort -> init(cmd.interface, name)

cli.command 'upgrade'
.description 'upgrades project files to current installed version of re-natal (the upgrade of re-natal itself is done via npm)'
.action ->
  doUpgrade readConfig(false)

cli.command 'add-platform <platform>'
  .description 'adds additional app platform: \'windows\' - UWP app, \'wpf\' - WPF app'
  .action (platform) ->
    addPlatform(platform)

cli.command 'xcode'
  .description 'open Xcode project'
  .action ->
    ensureOSX ->
      ensureXcode ->
        openXcode readConfig().name

cli.command 'deps'
  .description 'install all dependencies for the project'
  .action ->
    installDeps(verbose: true, report: true)

cli.command 'use-figwheel'
  .description 'generate index.*.js for development with figwheel'
  .action () ->
    generateDevScripts()

cli.command 'use-android-device <type>'
  .description 'sets up the host for android device type: \'real\' - localhost, \'avd\' - 10.0.2.2, \'genymotion\' - 10.0.3.2, IP'
  .action (type) ->
    configureDevHostForAndroidDevice type

cli.command 'use-ios-device <type>'
  .description 'sets up the host for ios device type: \'simulator\' - localhost, \'real\' - auto detect IP on eth0, IP'
  .action (type) ->
    configureDevHostForIosDevice type

cli.command 'use-component <name> [<platform>]'
  .description 'configures a custom component to work with figwheel. name is the value you pass to (js/require) function.'
  .action (name, platform) ->
    useComponent(name, platform)

cli.command 'infer-components'
  .description 'parses all cljs files in this project, extracts all (js/require) components calls and uses them to populate the re-natal file'
  .action () ->
    inferComponents()

cli.command 'enable-source-maps'
.description 'patches RN packager to server *.map files from filesystem, so that chrome can download them.'
.action () ->
  patchReactNativePackager()

cli.command 'copy-figwheel-bridge'
  .description 'copy figwheel-bridge.js into project'
  .action () ->
    copyFigwheelBridge(readConfig(false).name)
    log "Copied figwheel-bridge.js"

cli.on '*', (command) ->
  logErr "unknown command #{command[0]}. See re-natal --help for valid commands"


unless semver.satisfies process.version[1...], nodeVersion
  logErr """
         Re-Natal requires Node.js version #{nodeVersion}
         You have #{process.version[1...]}
         """

if process.argv.length <= 2
  cli.outputHelp()
else
  cli.parse process.argv
