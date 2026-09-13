const fs = require("fs");
const path = require("path");
const parser = require(process.argv[2] || "luaparse");
const files = [];
function walk(dir) {
    for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
        const target = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(target);
        else if (target.endsWith(".lua")) files.push(target);
    }
}
walk("lua");
walk("tests");
for (const file of files) parser.parse(fs.readFileSync(file, "utf8"), {luaVersion: "5.1"});
const language = fs.readFileSync("lua/terrortown/lang/en/test_round_toolkit.lua", "utf8");
const keys = new Set([...language.matchAll(/L\.(trt_\w+)\s*=/g)].map(match => match[1]));
for (const file of files.filter(file => file.startsWith("lua"))) {
    for (const match of fs.readFileSync(file, "utf8").matchAll(/"(trt_\w+)"/g)) {
        if (!keys.has(match[1])) throw new Error("Missing translation: " + match[1]);
    }
}
console.log(files.length + " Lua files parse as Lua 5.1");
console.log(keys.size + " English translation keys; all references resolved");
