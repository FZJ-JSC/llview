var icons = {
    "Live": "television",
    "System": "cog",
    "Queue": "list",
    "Workflows": "list-alt",
    "Job Reporting": "play",
    "Active jobs": "play",
    "History": "calendar",
    "Users/Projects": "user",
    "Internal": "database",
    "Help": "question",
    "Benchmarks": "bar-chart",
    "Known Issues": "exclamation-triangle",
    "Contact": "envelope-o",
    "Access": "sign-in",
    "Installation": "download",
    "Description": "file-text"
}

$("nav.md-tabs li a").each((id,el) => {
    let text = el.innerHTML.trim();
    if (text in icons) {
        el.innerHTML = el.innerHTML.replace(text,`<span class="fa fa-${icons[text]}" style="padding: 0.3em"></span> ${text}`)
    }
})
$("nav.md-nav li label").each((id,el) => {
    let text = el.innerText.trim();
    if (text in icons) {
        el.innerHTML = el.innerHTML.replace(text,`<span class="fa fa-${icons[text]}" style="padding-right: 0.5em"></span> ${text}`)
    }
})
