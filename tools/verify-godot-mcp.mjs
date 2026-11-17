// Connect to the installed MCP server over its real stdio transport.
import {Client} from './godot-mcp-runtime/node_modules/@modelcontextprotocol/sdk/dist/client/index.js';
import {StdioClientTransport} from './godot-mcp-runtime/node_modules/@modelcontextprotocol/sdk/dist/client/stdio.js';
import {writeFileSync, mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const transport = new StdioClientTransport({command: process.execPath, args:[root+'tools/godot-mcp-runtime/build/index.js'], env:{...process.env,GODOT_PATH:'D:\\downloads\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64_console.exe'}});
const client = new Client({name:'cas-godot-verifier', version:'1.0.0'}, {capabilities:{}});
try {
  await client.connect(transport);
  const listing = await client.listTools();
  const version = await client.callTool({name:'get_godot_version',arguments:{}});
  const result={schema_version:1,server:client.getServerVersion(),tool_names:listing.tools.map(t=>t.name),version};
  if(version.isError || !JSON.stringify(version).includes('4.7.2')) throw Error(JSON.stringify(version));
  mkdirSync(root+'artifacts/godot',{recursive:true});
  writeFileSync(root+'artifacts/godot/mcp-receipt.json',JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result));
} finally { await client.close(); }
