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
                vscode_1.window.showInformationMessage(`Roblox LSP: Updated API (${lastVersion}). [View changes](https://clonetrooper1019.github.io/Roblox-API-History.html)`);
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

function openUpdatesWindow(context) {
    try {
        const sawUpdate = fs.readFileSync(context.asAbsolutePath(path.join('client', 'sawupdate.txt')), 'utf8')
        if (sawUpdate == "false") {
            writeToFile(context.asAbsolutePath(path.join('client', 'sawupdate.txt')), "true");
            const panel = vscode_1.window.createWebviewPanel(
                'robloxlspUpdates', // Identifies the type of the webview. Used internally
                'Roblox LSP Updates', // Title of the panel displayed to the user
                vscode_1.ViewColumn.One, // Editor column to show the new webview panel in.
                {} // Webview options. More on these later.s
            );
        
            panel.webview.html = `<!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
            </head>
            <body>
                <div style="position:relative; padding-left:100px; padding-right:100px">
                    <center><img src="https://t3.rbxcdn.com/7bdf9c64b9c096d7db26bf8927213f2a", witdh="300" height="300"></center>
                    <h1 style="font-size:3rem; font-weight:100">Roblox LSP Updates! (0.14.0)</h1>
                    <hr style="height:2px;border:none;color:#333;background-color:#333;"/>
                    <p style="font-size:1rem">This is one of the latest updates I will make for Roblox LSP in a while, this update comes with three nice features.</p>
                    <p style="font-size:1rem">Report any bug or question here: <a href="https://github.com/NightrainsRbx/RobloxLsp/issues">https://github.com/NightrainsRbx/RobloxLsp/issues</a></p>
                    <h2 style="font-size:2rem; font-weight:100">Auto-updatable Roblox API</h2>
                    <p style="font-size:1rem">You will no longer have to wait for the extension to update when Roblox adds a new function.</p>
                    <p style="font-size:1rem">Every time you start the extension it will check if there is a new version of Roblox and if there is it will automatically download the API from <a href="https://github.com/CloneTrooper1019/Roblox-Client-Tracker">https://github.com/CloneTrooper1019/Roblox-Client-Tracker</a>.</p>
                    <p style="font-size:1rem">And you will receive this notification:</p>
                    <img src="https://i.imgur.com/U0Sw31z.png">
                    <h2 style="font-size:2rem; font-weight:100">Autocompletion for descendants in game</h2>
                    <p style="font-size:1rem">Roblox LSP can now receive information from Roblox Studio using a plugin, if you install it, a list of every descendant in your game will be send to Roblox LSP every time you create, remove, move or rename an Instance.</p>
                    <img src="https://media.discordapp.net/attachments/434146484758249482/778145929345368064/test.gif" width="653" height="430">
                    <p style="font-size:1rem">To use this feature, install the plugin <a href="https://www.roblox.com/library/5969291145/Roblox-LSP-Plugin">here</a>, and two buttons will appear in the Toolbar called <strong>Connect</strong> to start sending data to this extension, and <strong>Settings</strong> to configure the plugin.</p>
                    <p style="font-size:1rem">Roblox LSP will be ready to receive data when you initialize the extension, it uses a port in localhost, you can configure the port changing the setting "Lua.completion.serverPort". You can also configure the plugin to make it start automatically when you open the place, exclude instances and their descendants, or change the port, both ports must match. It is recommended to use a different port for every project.</p>
                    <p style="font-size:1rem">You can check the data sent to localhost in <a href="http://127.0.0.1:PORT/last">http://127.0.0.1:PORT/last</a>.</p>
                    <p style="font-size:1rem">The old method of using .datamodel.json files is now deprecated and disabled, but it can be enabled in a future version to allow custom autocompletion.</p>
                    <h2 style="font-size:2rem; font-weight:100">Much better "Undefined member" diagnostic</h2>
                    <p style="font-size:1rem">undefined-rbx-member warning no longer appears when you index an Instance to get a value, instead, it only appears when you index it to set a value or call the index, for example:</p>
                    <img src="https://doy2mn9upadnk.cloudfront.net/uploads/default/original/4X/c/8/8/c886003e56880e182cc747bfd3a128f0414c8bf9.png" width="596" height="436"">
                    <p style="font-size:1rem">It still works the same when indexing a DataType like BrickColor, since it can't have children.</p>
                    <h2 style="font-size:2rem; font-weight:100">Updates from other versions</h2>
                    <p style="font-size:1rem">0.13.1</p>
                    <ul>
                        <li>Added new table.clear function</li>
                        <li>Improved number operations with Roblox types</li>
                        <li>Added "--ignore" comment for ignore diagnostics in a line</li>
                        <li>Fixed API</li>
                    </ul>
                    <p style="font-size:1rem">0.13.0</p>
                    <ul>
                        <li>Added out-of-the-box support for Roact, Rodux, AGF, Knit and TestEz</li>
                    </ul>
                    <p style="font-size:1rem">0.12.1</p>
                    <ul>
                        <li>Improved missing-module-return and continue statement</li>
                    </ul>
                    <p style="font-size:1rem">0.12.0</p>
                    <ul>
                        <li>Added "missing-module-return" diagnostics that checks if your ModuleScript has a return</li>
                        <li>Updated Luau syntax support</li>
                    </ul>
                    <h2 style="font-size:2rem; font-weight:100">Future plans for Roblox LSP</h2>
                    <p style="font-size:1rem">Roblox LSP uses Lua Language Server by sumneko as its base, thanks to that, it's capable of a lot of things, and it's written in Lua, but it consumes a lot of memory and cpu with long files, which is the main problem of Roblox LSP.</p>
                    <p style="font-size:1rem">For a long time, a new version of Lua Language Server has been working from scratch, this is much faster and more efficient, Roblox LSP will use this new version when it is stable enough.</p>
                    <p style="font-size:1rem">And for that version I plan to implement new features like a basic optional type checking based on Luau.</p>
                    <p style="font-size:1rem">But Roblox LSP will be deprecated if Roblox decides to make its own LSP for Luau that is compatible with external editors and is superior in every way, which is possible that they do next year.</p>
                    <p style="font-size:1rem">More info about Roblox LSP: <a href="https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745">https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745</a></p>
                </div>
            </body>
            </html>`;
        }
    } catch (err) {}
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

    openUpdatesWindow(context)

    if (vscode_1.workspace.getConfiguration().get("Lua.runtime.version") == "Luau") {
        updateRobloxAPI(context);
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