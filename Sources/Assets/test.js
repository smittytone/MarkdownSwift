let Mdn = require('./markdown-it');
let md = new Mdn();

let output = md.render("# Headline\nThis is some **bold** text, plus _italic_.");
console.log(output);
