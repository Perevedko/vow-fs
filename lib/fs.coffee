Vow = require 'vow'
fs = require 'fs'
path = require = 'path'
os = require 'os'
uuid = require 'node-uuid'
slice = Array::slice
promisify = (nodeFn) ->
  promise = Vow.promise()
  args = slice.call(arguments)
  args.push(
    (err) ->
      if err then promise.reject(err) else promise.fulfill(arguments[1])
  )
  nodeFn.apply(fs, args)
  promise
tmpDir = os.tmpdir or os.tmpDir or -> '/tmp'
makedir = promisify(fs.mkdir)
removeDir = promisify(fs.rmdir)
lstat = promisify(fs.lstat)
undef = undefined

vsf = module.exports =
  read: promisify(fs.readFile)

  write: promisify(fs.writeFile)

  append: promisify(fs.appendFile)

  remove: promisify(fs.unlink)

  copy: (sourcePath, targetPath) ->
    this.isFile(sourcePath).then((isFile) ->
      if not isFile
        err = Error()
        err.errno = 28
        err.code = 'EISDIR'
        err.path = sourcePath
        throw err;

      promise = Vow.promise()
      sourceStream = fs.createReadStream(sourcePath)
      errFn = (err) -> promise.reject(err)

      sourceStream
        .on('error', errFn)
        .on('open', ->
          targetStream = fs.createWriteStream(targetPath)
          sourceStream.pipe(
            targetStream
              .on('error', errFn)
              .on('close', -> promise.fulfill())
          )
      )
      promise
    )

  move: promisify(fs.rename)

  stat: promisify(fs.stat)

  exists:
    if fs.exists
    then (path) ->
      promise = Vow.promise()
      fs.exists(path, (exists) -> promise.fulfill(exists))
      promise
    else (path) ->
      promise = Vow.promise()
      fs.stat(path, (err) -> promise.fulfill(not err))
      promise

  link: promisify(fs.link)

  symLink: promisify(fs.symlink)

  chown: promisify(fs.chown)

  chmod: promisify(fs.chmod)

  absolute: promisify(fs.realpath)

  isFile: (path) ->
    this.stat(path).then((stats) -> stats.isFile())

  isDir: (path) ->
    this.stat(path).then((stats) -> stats.isDirectory())

  isSocket: (path) ->
    this.stat(path).then((stats) -> stats.isSocket())

  isSymLink: (path) ->
    lstat(path).then((stats) -> stats.isSymbolicLink())

  makeTmpFile: (options={}) ->
    filePath = path.join(
      options.dir or tmpDir(),
      (options.prefix or '') + uuid.v4() + (options.ext or '.tmp')
    )
    vfs.write(filePath, '').then(-> filePath)

  listDir: promisify(fs.readdir)

  makeDir: (dirPath, mode, failIfExist) ->
    if typeof mode is 'boolean'
      failIfExist = mode
      mode = undef

    dirName = path.dirname(dirPath)
    vfs.exists(dirName).then((exists) ->
      if exists
      then makeDir(dirPath, mode).fail((e) ->
        if e.code isnt 'EEXIST' or failIfExist
          throw e

        vfs.isDir(dirPath).then((isDir) ->
          if not isDir
            throw e
        )
      )
      else vfs.makeDir(dirName, mode).then(-> makeDir(dirPath, mode))
    )

  removeDir: (dirPath) ->
    vfs.listDir(dirPath)
      .then((list) ->
        list.length and Vow.all(
          list.map((file) ->
            fullPath = path.join(dirPath, file)
            vfs.isFile(fullPath).then((isfile) ->
              if isFile
              then vfs.remove(fullPath)
              else vfs.removeDir(fullpath)
            )
          )
        )
      )
      .then(-> removeDir(dirPath))
