"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const path = require("path");
const os = require("os");
const fs = require("fs");
const vscode_1 = require("vscode");
const express = require("express");
let patch = require("./patch");
const node_1 = require("vscode-languageclient/node");
const vscode_2 = require("vscode");

let client;

let app;
let server;

function registerCustomCommands(context) {
    context.subscriptions.push(vscode_2.commands.registerCommand('lua.config', (data) => {
        let config = vscode_1.workspace.getConfiguration();
        if (data.action == 'add') {
            let value = config.get(data.key);
            value.push(data.value);
            config.update(data.key, value);
            return;
        }
        if (data.action == 'set') {
            config.update(data.key, data.value);
            return;
        }
    }));
}

function startPluginServer() {
    try {
        app = express();
        app.use('/update', express.json({
            limit: '10mb',
        }));
        let lastUpdate = "";
        app.post('/update', async (req, res) => {
            if (!req.body) {
                res.status(400);
                res.json({
                    success: false,
                    reason: 'Missing JSON',
                });
                return;
            }
            if (!req.body.DataModel) {
                res.status(400);
                res.json({
                    success: false,
                    reason: 'Missing body.DataModel',
                });
                return;
            }
            try {
                vscode_1.commands.executeCommand("lua.updateDatamodel", {
                    "datamodel": req.body.DataModel
                });
                lastUpdate = req.body.DataModel;
            }
            catch (e) {
                vscode_1.window.showErrorMessage(e);
            }
            res.status(200);
            res.json({success: true});
        });
        app.get("/last", (req, res) => {
            res.send(lastUpdate);
        });
        let port = vscode_1.workspace.getConfiguration().get("Lua.completion.serverPort");
        if (port > 0) {
            // server = app.listen(port);
            server = app.listen(port, () => {
                vscode_1.window.showInformationMessage(`Started Roblox LSP Plugin Server on port ${port}`);
            });
        }
    }
    catch (e) {
        vscode_1.window.showErrorMessage(`Failed to launch Roblox LSP plugin server: ${e}`);
    }
}

function activate(context) {
    let language = vscode_1.env.language;
    // Options to control the language client
    let clientOptions = {
        // Register the server for plain text documents
        documentSelector: [{ scheme: 'file', language: 'lua' }],
        synchronize: {
            // Notify the server about file changes to '.clientrc files contained in the workspace
            fileEvents: vscode_1.workspace.createFileSystemWatcher('**/.clientrc')
        }
    };
    let beta = vscode_1.workspace.getConfiguration().get("Lua.zzzzzz.cat");
    //let beta: boolean = false;
    let develop = false //vscode_1.workspace.getConfiguration().get("Lua.develop.enable");
    let debuggerPort = 11412 //vscode_1.workspace.getConfiguration().get("Lua.develop.debuggerPort");
    let debuggerWait = false //vscode_1.workspace.getConfiguration().get("Lua.develop.debuggerWait");
    let command;
    
    let platform = os.platform();
    switch (platform) {
        case "win32":
            command = context.asAbsolutePath(path.join('server', 'bin', 'Windows', 'lua-language-server.exe'));
            break;
        case "linux":
            command = context.asAbsolutePath(path.join('server', 'bin', 'Linux', 'lua-language-server'));
            fs.chmodSync(command, '777');
            break;
        case "darwin":
            command = context.asAbsolutePath(path.join('server', 'bin', 'macOS', 'lua-language-server'));
            fs.chmodSync(command, '777');
            break;
    }
    
    let serverOptions = {
        command: command,
        args: [
            '-E',
            '-e',
            `LANG="${language}";DEVELOP=${develop};DBGPORT=${debuggerPort};DBGWAIT=${debuggerWait}`,
            context.asAbsolutePath(path.join('server', beta ? 'main-beta.lua' : 'main.lua'))
        ]
    };

    if (vscode_1.workspace.getConfiguration().get("Lua.runtime.version") == "Luau") {
        startPluginServer();
    }

    client = new node_1.LanguageClient('Lua', 'Lua', serverOptions, clientOptions);

    client.registerProposedFeatures();
    registerCustomCommands(context);
    patch.patch(client);
    client.start();
}
exports.activate = activate;
function deactivate() {
    if (!client) {
        return undefined;
    }
    if (server) {
        server.close();
        server = undefined;
    }
    return client.stop();
}
exports.deactivate = deactivate;
//# sourceMappingURL=languageserver.js.map