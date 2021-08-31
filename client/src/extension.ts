import * as vscode from 'vscode'
import * as languageserver from './languageserver';
import * as fetch from 'node-fetch';
import * as path from 'path';
import * as fs from 'fs';
import * as express from 'express';
import { Server } from 'http';

let server: Server | undefined;

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
                vscode.commands.executeCommand("robloxLsp.updateDatamodel", {
                    "datamodel": req.body.DataModel,
                    "version": req.body.Version
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
        let port = vscode.workspace.getConfiguration().get("robloxLsp.misc.serverPort");
        if (port > 0) {
            server = app.listen(port, () => {
                // vscode.window.showInformationMessage(`Started Roblox LSP Plugin Server on port ${port}`);
            });
        }
    } catch (err) {
        vscode.window.showErrorMessage(`Failed to launch Roblox LSP plugin server: ${err}`);
    }
}

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
                // fetchData('https://raw.githubusercontent.com/NightrainsRbx/RobloxLsp/master/server/rbx/datatypes.json', (data) => {
                //     writeToFile(context.asAbsolutePath(path.join('server', 'rbx', 'datatypes.json')), data);
                // });
                writeToFile(context.asAbsolutePath(path.join('server', 'rbx', 'version.txt')), lastVersion);
                vscode.window.showInformationMessage(`Roblox LSP: Updated API (${lastVersion}). [View changes](https://clonetrooper1019.github.io/Roblox-API-History.html)`);
            }
        } catch (err) {
            vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
        }
    });
}

async function openUpdatesWindow(context: vscode.ExtensionContext) {
    if (context.globalState.get("sawVersionLogNew", false) == false) {
        const panel = vscode.window.createWebviewPanel(
            'robloxlspUpdates',
            'Roblox LSP Updates',
            vscode.ViewColumn.One,
            {}
        );
        panel.webview.html = `<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body>
            <div style="position:relative; padding-left:100px; padding-right:100px">
                <center><img src="https://i.imgur.com/PH5u9QD.png", witdh="300" height="300"></center>
                <h1 style="font-size:3rem; font-weight:100">Roblox LSP Updates!</h1>
                <hr style="height:2px;border:none;color:#333;background-color:#333;"/>
                <p style="font-size:1rem">More info: <a href="https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745">https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745</a></p>
                <p style="font-size:1rem">Report any bug or question here: <a href="https://github.com/NightrainsRbx/RobloxLsp/issues">https://github.com/NightrainsRbx/RobloxLsp/issues</a></p>
                <hr style="height:2px;border:none;color:#333;background-color:#333;"/>
                <h2 style="font-size:2rem; font-weight:100">1.0.0</h2>

                <li style="font-size:1rem">Roblox LSP got updated to Lua by sumneko 1.21.3! This version has new features like inlay hints, plugins, external libraries and more.</li>
                <li style="font-size:1rem">Much faster, stable and intelligent.</li>
                <li style="font-size:1rem">All features have been reworked and improved.</li>
                <li style="font-size:1rem">Pretty much everything has changed so I will not specify the details here, I'll document the most important features on the github wiki page soon.</li>
                <h2 style="font-size:2rem; font-weight:100">Luau Intellisense and Typechecking</h2>
                <p style="font-size:1rem">Roblox LSP is now able to understand Luau type annotations, to provide full intellisense, and even type checking!</p>
                <p style="font-size:1rem">Typechecking is in BETA right now, and disabled by default, don't use it in serious projects yet. Features that need to be implemeted:</p>
                <ul>
                    <li>Type Refinements and custom Type Predicates.</li>
                    <li>Support for Metatables, at the moment, setting a metatable will result in a union of the __index field of the metatable and the table.</li>
                    <li>Compatibility check for Type Intersection.</li>
                    <li>Generic for Functions (to be used internally like in Roblox Studio).</li>
                    <li>Much better type inference.</li>
                </ul>
                <p style="font-size:1rem">If you want to test typechecking, set "robloxLsp.typeChecking.mode" to "Strict" or "Non Strict". Intellisense is enabled by default.</p>
                <p style="font-size:1rem">Type checking in Roblox LSP is heavily based on the official Luau type checking, but it's not completely the same, and it's not intended to be. For more details, check: <a href="https://github.com/NightrainsRbx/RobloxLsp/wiki/Type-Checking">https://github.com/NightrainsRbx/RobloxLsp/wiki/Type-Checking</a></p>
                <h2 style="font-size:2rem; font-weight:100">Focusing only on Roblox</h2>
                <p style="font-size:1rem">The namespace for the settings in Roblox LSP is now "robloxLsp" instead of "Lua", also, from now Roblox LSP doesn't support other versions of Lua like Lua 5.1 to LuaJIT, to work with these versions, install Lua by sumneko separately.</p>
                <p style="font-size:1rem">I recommend not disabling the settings you used to have disabled in the previous version, since they are much better now, you should give them a second chance.</p>
                <p style="font-size:1rem">The setting "Lua.diagnostics.syntaxErrors" has been removed, to use Selene, disable diagnostics completely, this will also disable syntax errors. Type checking will not be affected by this.</p>
            </div>
        </body>
        </html>`;
        await context.globalState.update("sawVersionLogNew", true);
    }
}

export function activate(context: vscode.ExtensionContext) {
    try {
        if (vscode.extensions.getExtension("sumneko.lua") != undefined) {
            vscode.window.showErrorMessage("The extension [Lua](https://marketplace.visualstudio.com/items?itemName=sumneko.lua) by sumneko is enabled, please disable it so that Roblox LSP can work properly.");
        }
    } catch (err) {
        vscode.window.showErrorMessage(err);
    }

    openUpdatesWindow(context);

    updateRobloxAPI(context);

    languageserver.activate(context);

    startPluginServer();
}

export function deactivate() {
    if (server != undefined) {
        server.close();
        server = undefined;
    }
    languageserver.deactivate();
}
