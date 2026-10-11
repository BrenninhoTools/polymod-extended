const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const state = {
  requests: {},
  notModified: 0,
  gameBananaFileId: 9001,
  base: ""
};

function md5(data) {
  return crypto.createHash("md5").update(data).digest("hex");
}

function gameBananaProfile(goodMd5) {
  const memory = fs.readFileSync(path.join(process.cwd(), "fixtures", "memory_mod.zip"));
  return JSON.stringify({
    _idRow: 123,
    _sName: "Memory Mod",
    _sVersion: "1.0",
    _tsDateUpdated: 1700000000 + state.gameBananaFileId,
    _aFiles: [
      { _idRow: 1, _sFile: "old_version.zip", _sDownloadUrl: state.base + "/missing.zip", _bIsArchived: true, _sAvResult: "clean" },
      { _idRow: 2, _sFile: "bad.zip", _sDownloadUrl: state.base + "/missing.zip", _bIsArchived: false, _sAvResult: "infected" },
      {
        _idRow: state.gameBananaFileId,
        _sFile: "memory_mod.zip",
        _nFilesize: memory.length,
        _sDownloadUrl: state.base + "/fixtures/memory_mod.zip",
        _sMd5Checksum: goodMd5 ? md5(memory) : "00000000000000000000000000000000",
        _bIsArchived: false,
        _sAvResult: "clean",
        _sVersion: "1.0"
      },
      { _idRow: 4, _sFile: "extras.7z", _nFilesize: 10, _sDownloadUrl: state.base + "/extras.7z", _bIsArchived: false, _sAvResult: "clean" }
    ]
  });
}

function handle(request, response) {
  const url = decodeURIComponent(request.url.split("?")[0]);
  state.requests[url] = (state.requests[url] || 0) + 1;

  if (url === "/api/Mod/123/ProfilePage" || url === "/api/Mod/124/ProfilePage") {
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(gameBananaProfile(url.indexOf("123") !== -1));
    return;
  }

  if (url === "/redirect/zip_mod.zip") {
    response.writeHead(302, { Location: "/mods/zip_mod.zip" });
    response.end();
    return;
  }

  if (url === "/big.zip") {
    response.writeHead(200, { "Content-Length": String(10 * 1024 * 1024) });
    response.write(Buffer.alloc(1024));
    setTimeout(() => response.destroy(), 200);
    return;
  }

  if (url === "/slow.zip") {
    const data = fs.readFileSync(path.join(process.cwd(), "fixtures", "memory_mod.zip"));
    response.writeHead(200, { "Content-Length": String(data.length) });
    response.write(data.subarray(0, 100));
    const timer = setTimeout(() => response.end(data.subarray(100)), 3000);
    response.on("close", () => clearTimeout(timer));
    return;
  }

  if (url === "/named") {
    const data = fs.readFileSync(path.join(process.cwd(), "mods", "zip_mod.zip"));
    response.writeHead(200, { "Content-Disposition": 'attachment; filename="named_mod.zip"', "Content-Length": String(data.length) });
    response.end(data);
    return;
  }

  const file = path.join(process.cwd(), url);

  fs.readFile(file, (error, data) => {
    if (error) {
      response.writeHead(404);
      response.end("not found");
      return;
    }

    const etag = '"' + md5(data) + '"';

    if (request.headers["if-none-match"] === etag) {
      state.notModified++;
      response.writeHead(304, { ETag: etag });
      response.end();
      return;
    }

    response.writeHead(200, { ETag: etag, "Content-Length": String(data.length) });
    response.end(data);
  });
}

function start() {
  return new Promise((resolve) => {
    const server = http.createServer(handle);
    server.listen(0, "127.0.0.1", () => {
      state.base = "http://127.0.0.1:" + server.address().port;
      resolve(server.address().port);
    });
    server.unref();
  });
}

module.exports = { start, state };
