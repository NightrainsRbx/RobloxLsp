import * as vscode from 'vscode'
import * as languageserver from './languageserver';

import * as fs from 'fs';
import * as path from 'path';
import * as express from 'express';
import * as fetch from 'node-fetch';

import { Server } from 'http';

let server: Server | undefined;

const fetchData = async (url: string, handler: (data: string) => void) => {
    try {
        fetch.default(url)
            .then(res => res.text())
            .then(body => handler(body));
    } catch (err) {
        vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
    }
};

function writeToFile(path: string, content: string) {
    try {
        fs.writeFileSync(path, content);
    } catch (err) {
        vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
    }
}

function updateRobloxAPI(context: vscode.ExtensionContext) {
    fetchData('https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/version.txt', (lastVersion) => {
        try {
            const currentVersion = fs.readFileSync(context.asAbsolutePath(path.join('server', 'rbx', 'version.txt')), 'utf8')
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
                writeToFile(context.asAbsolutePath(path.join('server', 'rbx', 'version.txt')), lastVersion);
                vscode.window.showInformationMessage(`Roblox LSP: Updated API (${lastVersion}). [View changes](https://clonetrooper1019.github.io/Roblox-API-History.html)`);
            }
        } catch (err) {
            vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
        }
    });
}

function startPluginServer() {
    try {
        let lastUpdate = "";
        let app = express();
        app.use('/update', express.json({
            limit: '10mb',
        }));
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
                vscode.commands.executeCommand("lua.updateDatamodel", {
                    "datamodel": req.body.DataModel
                });
                lastUpdate = req.body.DataModel;
            } catch (err) {
                vscode.window.showErrorMessage(err);
            }
            res.status(200);
            res.json({success: true});
        });
        app.get("/last", (req, res) => {
            res.send(lastUpdate);
        });
        let port = vscode.workspace.getConfiguration().get("Lua.completion.serverPort");
        if (port > 0) {
            server = app.listen(port);
            // server = app.listen(port, () => {
            //     vscode.window.showInformationMessage(`Started Roblox LSP Plugin Server on port ${port}`);
            // });
        }
    } catch (err) {
        vscode.window.showErrorMessage(`Failed to launch Roblox LSP plugin server: ${err}`);
    }
}

let luadoc = require('../3rd/vscode-lua-doc/extension.js')

interface LuaDocExtensionContext extends vscode.ExtensionContext {
    readonly ViewType: string;
    readonly OpenCommand: string;
}

export function activate(context: vscode.ExtensionContext) {
    languageserver.activate(context);

    try {
        if (vscode.extensions.getExtension("sumneko.lua") != undefined) {
            vscode.window.showErrorMessage("The extension [Lua](https://marketplace.visualstudio.com/items?itemName=sumneko.lua) by sumneko is enabled, please disable it so that Roblox LSP can work properly.");
        }
    } catch (err) {
        vscode.window.showErrorMessage(err);
    }

    if (vscode.workspace.getConfiguration().get("Lua.runtime.version") == "Luau") {
        updateRobloxAPI(context);
        startPluginServer();
    }

    let luadocContext: LuaDocExtensionContext = {
        subscriptions:                 context.subscriptions,
        workspaceState:                context.workspaceState,
        globalState:                   context.globalState,
        extensionPath:                 context.extensionPath + '/client/3rd/vscode-lua-doc',
        asAbsolutePath:                context.asAbsolutePath,
        storagePath:                   context.storagePath,
        globalStoragePath:             context.globalStoragePath,
        logPath:                       context.logPath,
        extensionUri:                  context.extensionUri,
        storageUri:                    context.storageUri,
        globalStorageUri:              context.globalStorageUri,
        logUri:                        context.logUri,
        environmentVariableCollection: context.environmentVariableCollection,
        extensionMode:                 context.extensionMode,
        ViewType:                      'lua-doc',
        OpenCommand:                   'extension.lua.doc',
    };

    luadoc.activate(luadocContext);
}

export function deactivate() {
    languageserver.deactivate();
    if (server != undefined) {
        server.close();
        server = undefined;
    }
}
