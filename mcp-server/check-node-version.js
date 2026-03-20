// Guard: MCP server requires Node.js >= 18
const major = parseInt(process.versions.node.split('.')[0], 10);
if (major < 18) {
  process.stderr.write(
    `Claude Octopus MCP server requires Node.js >= 18 (found ${process.versions.node}). ` +
    'Upgrade Node.js or the MCP server will not start.\n'
  );
  process.exit(1);
}
