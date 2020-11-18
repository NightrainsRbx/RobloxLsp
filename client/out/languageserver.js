"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const path = require("path");
const os = require("os");
const fs = require("fs");
const vscode_1 = require("vscode");
let patch = require("./patch");
const node_1 = require("vscode-languageclient/node");
const vscode_2 = require("vscode");

const express = require("express");
const fetch = require("node-fetch");

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

const fetchData = async (url, handler) => {
    try {
        fetch(url)
            .then(res => res.text())
            .then(body => handler(body));
    } catch (error) {
        vscode_1.window.showErrorMessage(`Roblox LSP Error: ${error}`);
    }
};

function writeToFile(path, content) {
    try {
        fs.writeFileSync(path, content);
    } catch (err) {
        vscode_1.window.showErrorMessage(`Roblox LSP Error: ${err}`);
    }
}

function updateRobloxAPI(context) {
    fetchData('https://clientsettings.roblox.com/v1/client-version/WindowsStudio', (lastVersion) => {
        try {
            const currentVersion = fs.readFileSync(context.asAbsolutePath(path.join('server', 'rbx', 'version.json')), 'utf8')
            if (currentVersion != lastVersion) {
                fetchData('https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/AutocompleteMetadata.xml', (data) => {
                    writeToFile(context.asAbsolutePath(path.join('server', 'rbx', 'AutocompleteMetadata.xml')), data);
                });
                fetchData('https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml', (data) => {
                    writeToFile(context.asAbsolutePath(path.join('server', 'rbx', 'ReflectionMetadata.xml')), data);
                });
                fetchData('https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json', (data) => {
                    writeToFile(context.asAbsolutePath(path.join('server', 'rbx', 'API-Dump.json')), data);
                });
                writeToFile(context.asAbsolutePath(path.join('server', 'rbx', 'version.json')), lastVersion);
                vscode_1.window.showInformationMessage("Roblox LSP: Updated API");
            }
        } catch (err) {
            vscode_1.window.showErrorMessage(`Roblox LSP Error: ${err}`);
        }
    });
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
            server = app.listen(port);
            // server = app.listen(port, () => {
            //     vscode_1.window.showInformationMessage(`Started Roblox LSP Plugin Server on port ${port}`);
            // });
        }
    }
    catch (e) {
        vscode_1.window.showErrorMessage(`Failed to launch Roblox LSP plugin server: ${e}`);
    }
}

function openUpdatesWindow() {
    const panel = vscode_1.window.createWebviewPanel(
        'robloxlspUpdates', // Identifies the type of the webview. Used internally
        'Roblox LSP Updates', // Title of the panel displayed to the user
        vscode_1.ViewColumn.One, // Editor column to show the new webview panel in.
        {} // Webview options. More on these later.
    );

    panel.webview.html = `<!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body>
        <div style="position:relative; padding-left:100px; padding-right:100px">
            <h1 style="font-size:3rem; font-weight:100">Roblox LSP Updates!</h1>
            <hr style="height:2px;border:none;color:#333;background-color:#333;"/>
        </div>
    </body>
    </html>`;
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
        updateRobloxAPI(context);
        startPluginServer();
    }

    // openUpdatesWindow()

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