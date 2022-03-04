import * as vscode from 'vscode'
import * as languageserver from './languageserver';
import * as fetch from 'node-fetch';
import * as path from 'path';
import * as fs from 'fs';

const fetchData = async (url: string, handler: (data: string) => void, resolve?: () => void) => {
    try {
        fetch.default(url)
            .then(res => res.text())
            .then(body => handler(body))
            .then(resolve);
    } catch (err) {
        vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
        if (resolve != undefined) {
            resolve();
        }
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
            const currentVersion = fs.readFileSync(context.asAbsolutePath(path.join('server', 'api', 'version.txt')), 'utf8')
            if (currentVersion != lastVersion) {
                vscode.window.withProgress({
                    location: vscode.ProgressLocation.Notification,
                    title: 'Roblox LSP: Updating API',
                    cancellable: false
                }, async () => {
                    return Promise.all([
                        new Promise<void>(resolve => {
                            fetchData('https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json', (data) => {
                                writeToFile(context.asAbsolutePath(path.join('server', 'api', 'API-Dump.json')), data);
                            }, resolve);
                        }),
                        new Promise<void>(resolve => {
                            fetchData('https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/api-docs/en-us.json', (data) => {
                                writeToFile(context.asAbsolutePath(path.join('server', 'api', 'API-Docs.json')), data);
                                resolve();
                            });
                        })
                    ]);
                }).then(() => {
                    vscode.window.showInformationMessage(`Roblox LSP: Updated API (${lastVersion}). [View changes](https://maximumadhd.github.io/Roblox-API-History)`, "Reload VSCode").then(async (item) => {
                        if (item == "Reload VSCode") {
                            vscode.commands.executeCommand('workbench.action.reloadWindow');
                        }
                    });
                });
                writeToFile(context.asAbsolutePath(path.join('server', 'api', 'version.txt')), lastVersion);
            }
        } catch (err) {
            vscode.window.showErrorMessage(`Roblox LSP Error: ${err}`);
        }
    });
}

async function openUpdatesWindow(context: vscode.ExtensionContext) {
    if (context.globalState.get("sawVersionLogNew12", false) == false) {
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
                <p style="font-size:1rem">More info: <a href="https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745">https://devforum.roblox.com/t/roblox-lsp-full-intellisense-for-roblox-and-luau/717745</a></p>
                <p style="font-size:1rem">Report any bug or question here: <a href="https://github.com/NightrainsRbx/RobloxLsp/issues">https://github.com/NightrainsRbx/RobloxLsp/issues</a></p>
                <hr style="height:2px;border:none;color:#333;background-color:#333;"/>
                <h2 style="font-size:2rem; font-weight:100">v1.5.6</h2>
                <li style="font-size:1rem">Improved syntax support for Luau.</li>
                <li style="font-size:1rem">Added basic syntax support for generic type packs and singleton types.</li>
                <li style="font-size:1rem">Implemented suggeted imports for modules (thanks to <a href="https://github.com/Corecii">@Corecii</a>, <a href="https://github.com/NightrainsRbx/RobloxLsp/pull/123">#123</a>)</li>
                <li style="font-size:1rem">Added Vector3 constants (thanks to <a href="https://github.com/aku-e">@aku-e</a>, <a href="https://github.com/NightrainsRbx/RobloxLsp/pull/145">#145</a>)</li>
                <li style="font-size:1rem">Color3.fromHex is no longer deprecated.</li>
                <li style="font-size:1rem">Fixed deprecated classes not having typings. (<a href="https://github.com/NightrainsRbx/RobloxLsp/issues/147">#147</a>)</li>
                <li style="font-size:1rem">Fixed embedded rojo projects not using their correct root name. (<a href="https://github.com/NightrainsRbx/RobloxLsp/issues/128">#128</a>)</li>
                <li style="font-size:1rem">Inlay hints are not displayed if the type is "none" or "any".</li>
                <li style="font-size:1rem">Fixed diagnostics for type aliases with the same names as built-in types.</li>
                <li style="font-size:1rem">Updated binaries.</li>
            </div>
        </body>
        </html>`;
        await context.globalState.update("sawVersionLogNew12", true);
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
}

export function deactivate() {
    languageserver.deactivate();
}
