# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview.
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH)
#    Matthias Lapu (CEA)

from tools import format_float_string,replace_vars

def CreateHTML( config,
                figs,
                navbar="",
                first="",
                overview="",
                nodelist="",
                timeline="",
                system_report="",
                filename="report.html"):
  """
  Collects together various html snippets from separate figures into a single html report page
  """
  html = """
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="UTF-8">
"""
  if loc := config['appearance'].get('fontawesome_location'):
    fontawesome_location = loc
  else:
    fontawesome_location = f"{replace_vars(config['appearance']['hostname'],config['appearance'])}/css/ext/font-awesome.min.css"

  html += f"""
  <link rel="stylesheet" href='{fontawesome_location}'>
  <link rel="icon" type="image/svg+xml"
      href="data:image/svg+xml,%3Csvg height='100%25' stroke-miterlimit='10' style='fill-rule:nonzero;clip-rule:evenodd;stroke-linecap:round;stroke-linejoin:round;' version='1.1' viewBox='0 0 32 32' width='100%25' xml:space='preserve' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'%3E%3Cpath d='M8.02154 13.6133L8.03331 23.6475L10.2411 23.6597L12.4489 23.6718L12.4489 25.7506L12.4489 27.8294L18.7334 27.8294L25.018 27.8294L25.018 26.6379L25.018 25.4464L20.0885 25.4464L15.1589 25.4464L15.1589 24.5587L15.1589 23.6709L17.869 23.6709L20.5791 23.6709L20.5791 22.456L20.5791 21.2412L17.869 21.2412L15.1589 21.2412L15.1589 14.4894L15.1589 7.73754L13.8039 7.73754L12.4489 7.73754L12.4489 14.4894L12.4489 21.2412L11.5844 21.2412L10.72 21.2412L10.72 12.4101L10.72 3.57898L9.36489 3.57898L8.00972 3.57898L8.02154 13.6133' fill='%23023d6b' fill-rule='evenodd' opacity='1' stroke='none'/%3E%3Cpath d='M15.0868 0.0309399C9.2877 0.347224 4.09586 3.83135 1.56139 9.10753C-0.520462 13.4413-0.520462 18.5745 1.56139 22.9083C5.1584 30.3963 13.8239 33.894 21.607 30.9994C25.9088 29.3995 29.3916 25.9168 30.9915 21.615C32.5077 17.538 32.307 12.997 30.4386 9.10753C28.097 4.233 23.5169 0.89078 18.1603 0.147847C17.6781 0.080936 16.1368-0.0254576 15.8598-0.0109727C15.7956-0.0076085 15.4477 0.0112218 15.0868 0.0309399M8.02154 13.6133L8.03331 23.6475L10.2411 23.6597L12.4489 23.6718L12.4489 25.7506L12.4489 27.8294L18.7334 27.8294L25.018 27.8294L25.018 26.6379L25.018 25.4464L20.0885 25.4464L15.1589 25.4464L15.1589 24.5587L15.1589 23.6709L17.869 23.6709L20.5791 23.6709L20.5791 22.456L20.5791 21.2412L17.869 21.2412L15.1589 21.2412L15.1589 14.4894L15.1589 7.73754L13.8039 7.73754L12.4489 7.73754L12.4489 14.4894L12.4489 21.2412L11.5844 21.2412L10.72 21.2412L10.72 12.4101L10.72 3.57898L9.36489 3.57898L8.00972 3.57898L8.02154 13.6133' fill='%23ffffff' fill-rule='evenodd' opacity='1' stroke='none'/%3E%3C/svg%3E" />
"""
  html += """
  <style>
  * { 
      -moz-box-sizing: border-box; 
      -webkit-box-sizing: border-box; 
      box-sizing: border-box;
  }
  /* 1. Enable smooth scrolling */
  html {
    scroll-behavior: smooth;
  }
  body {
    background-color: white;
    text-align: center;
    width: 100%;
    font-family: 'Liberation Sans', 'Arial', sans-serif;
    font-size: 14px;
    margin: 0 auto 80px auto;
    padding-left: 5%;
    padding-right: 5%;
  }
  table {
    text-align: left;
  }
  a {
    text-decoration: none;
  }
  a.anchor {
    display: block;
    position: relative;
    top: -60px;
    visibility: hidden;
  }
  a.simple:hover {
    background: transparent;
  }
  a.pdf{
    display: inline-block;
    position: relative;
  }
  a.pdf:link {
    color: gray !important;
  }
  a.pdf:visited {
    color: gray !important;
  }
  a.pdf:hover {
    color: red !important;
    background: white !important;
  }
  a.top:link {
    background: white !important;
    color: gray !important;
  }
  a.top:visited {
    background: white !important;
    color: black !important;
  }
  a.top:hover {
    background: white !important;
    color: red !important;
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  li {
    margin-left: 1rem;
    white-space: nowrap;
  }

  .menu-button {
    cursor: pointer;
    font-size: 18px;
    font-family: FontAwesome;
  }
  .menu-button::before {
    position: fixed;
    top: 10px;
    left: 5%;
    content:"\\f00d";
    opacity: 1;
    transition: opacity .3s, transform .3s;
    z-index: 20;
  }
  #toggle-menu:checked ~ .menu-button::before {
    transform: rotate(180deg) scale(1);
    opacity: 0;
  }
  .menu-button::after {
    position: fixed;
    top: 10px;
    left: 5%;
    content:"\\f0c9";
    opacity: 0;
    transition: opacity .3s, transform .3s;
    transform: rotate(-180deg) scale(.5);
    z-index: 20;
  }
  #toggle-menu:checked ~ .menu-button::after {
    transform: rotate(0deg) scale(1);
    opacity: 1;
  }
  .toggle-menu {
    display: none;
    
  }
  .toggle-menu:checked ~ main {
    grid-template-columns: 1fr ;
  }
  .toggle-menu:checked ~ main > nav { 
    display: none;
  }
  .toggle-menu:checked ~ main > div {
    grid-column: 1;
  }

  main {
    display: grid;
    grid-template-columns: 16em 1fr ;
    grid-auto-flow: row;
    width: 100%;
    margin: 0 auto 0 auto;
  }
  /* 2. Make toc sticky */
  main > nav {
    font-size: 9pt;
    text-align: left;
    position: sticky;
    top: 2rem;
    align-self: start;
    grid-column: 1;
    overflow-y: auto;
    height: 100vh;
  }
  main > div {
    grid-column: 2;
  }
  /* 3. ScrollSpy active styles (see JS tab for activation) */
  .section-toc li.active > a {
    color: #333;
    font-weight: 500;
  }
  /* Sidebar Navigation */
  .section-toc {
    padding-left: 0;
    padding-right: 0;
    border-right: 1px solid #efefef;
  }
  .section-toc a {
    text-decoration: none;
    display: block;
    padding: .125rem 0;
    color: #ccc;
    transition: all 50ms ease-in-out; /* 💡 This small transition makes setting of the active state smooth */
  }
  .section-toc a:hover,
  .section-toc a:focus {
    color: #666;
  }
  .section-toc li.visible > a {
    color: #111;
    padding-left: 5px; 
  }
  .section-toc-marker {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    z-index: -1; 
  }
  .section-toc-marker path {
    transition: all 0.3s ease; 
  }
  div.lockzoom {
    visibility: hidden;
  }
  div.node {
    margin: 2pt;
    padding: 5pt;
    display: inline-block;
    width: 250px;
    border: 2px solid black; 
    font-size: 10pt;
    text-align: center;
  }
  div.errornode {
    margin: 2pt;
    padding: 5pt;
    display: inline-block;
    width: 250px;
    border: 2px solid red; 
    font-size: 10pt;
    text-align: center;
  }
  table {
    border: 2px solid black;
    border-collapse: collapse;
  }
  td {
    padding: 5px 5px 5px 5px;
    font-size: 14px;
  }
  h1 {
    font-size: 22px;
    font-weight: bold;
    color: black;
  }
  h2 { 
    font-size: 17px;
    font-weight: bold;
  }
  hr { 
    border : 0;
    height: 5px; 
    background-image: linear-gradient(to right, rgba(0, 0, 0, 0), rgba(0, 0, 0, 0.75), rgba(0, 0, 0, 0)); 
    margin: 50px 0;
  }
  .js-plotly-plot .plotly .modebar { 
    margin-top: 5px; 
    margin-right: 9%; 
  }
  .js-plotly-plot .plotly.plotly [data-title]:after {
    white-space: pre;
  }
  a.modebar-btn {
      font-size: 25px !important;
  }
  /* Tooltip container */
  .tooltip {
    position: relative;
    display: inline-block;
  }

  .tooltip .tooltiptext,
  .tooltip .tooltiptextright {
    background-color: black;
    color: #fff;
    text-align: center;
    padding: 5px 0;
    border-radius: 6px;
    visibility: hidden;
    opacity: 0;
    transition: visibility 0.5s ease-in-out,opacity 0.5s ease-in-out;
    position: absolute;
    z-index: 11;
  }

  /* Tooltip text (top)*/
  .tooltip .tooltiptext {
    width: 120px;
    bottom: 110%;
    left: 50%; 
    margin-left: -60px; /* Use half of the width (120/2 = 60), to center the tooltip */
  }

  /* Tooltip text (right)*/
  .tooltip .tooltiptextright {
    top: -5px;
    left: 105%; 
  }

  .tooltip .tooltiptext::after,
  .tooltip .tooltiptextright::after {
    content: " ";
    position: absolute;
    border-width: 5px;
    border-style: solid;
    visibility: hidden;
    opacity: 0;
    transition: visibility 0.5s ease-in-out,opacity 0.5s ease-in-out;
    z-index: 12;
  }

  .tooltip .tooltiptext::after {
    top: 100%; /* At the bottom of the tooltip */
    left: 50%;
    margin-left: -5px;
    border-color: black transparent transparent transparent;
  }

  .tooltip .tooltiptextright::after {
    top: 50%;
    right: 100%; /* To the left of the tooltip */
    margin-top: -5px;
    border-color: transparent black transparent transparent;
  }

  /* Show the tooltip text when you mouse over the tooltip container */
  .tooltip:hover > .tooltiptext,
  .tooltip:hover > .tooltiptext::after,
  .tooltip:hover > .tooltiptextright,
  .tooltip:hover > .tooltiptextright::after {
    visibility: visible;
    opacity: 1;
  }

  .flipswitch {
    position: relative;
    background: white;
    height: 19px;
    width: 60px;
    -webkit-appearance: initial;
    border-radius: 3px;
    -webkit-tap-highlight-color: rgba(0, 0, 0, 0);
    outline: none;
    font-size: 12px;
    font-family: FontAwesome;
    cursor: pointer;
    border: 1px solid #ddd;
  }

  .flipswitch:after {
    position: absolute;
    top: 5%;
    display: block;
    line-height: 15px;
    width: 45%;
    height: 90%;
    background: #fff;
    box-sizing: border-box;
    text-align: center;
    transition: all 0.3s ease-in 0s;
    color: black;
    border: #888 1px solid;
    border-radius: 3px;
  }

  .flipswitch:after {
    left: 2%;
    content: attr(data-off-text); /* OFF - UNLOCK */
  }

  .flipswitch:checked:after {
    left: 53%;
    content: attr(data-on-text); /* ON - LOCK */
  }

  .rborder {
    border-right: 2px solid black;
  }
  .bborder {
    border-bottom: 2px solid black;
  }
  .shrink{
    -webkit-transform:scale(0.5);
    -moz-transform:scale(0.5);
    -ms-transform:scale(0.5);
    transform:scale(0.5);
  }
  #navbar {
    background: white; /* White background color */
    position: fixed; /* Make it stick/fixed */
    bottom: 0px;
    width: 90%; 
    margin: 0;
    padding: 0;
    transition: bottom 0.3s; /* Transition effect when sliding down (and up) */
    border-top: 1px solid black;
    border-left: 1px solid black;
    border-right: 1px solid black;
    border-radius: 5px 5px 0 0;
    z-index: 10;
  }
  @media print
  {    
    .no-print, .no-print *
    {
      display: none !important;
    }
    html, body {
      width:100%;
      height:auto;
      margin:auto;
      padding:0;
    }
    main {
      width: 100%;
      grid-template-columns: 1fr ;
    }
    .plotly-graph-div {
      break-inside: avoid;
    }
    #nodelist {
      margin-top: 50px;
      break-inside: avoid;
    }
  }
  </style>
"""
  html += """
  <script>
  var wsize = 0;
  var plots = null;
  var time_plots = null;
  var overview = null;
  var timeline = null;
  var catch_scroll = true;
  var repeat;
"""
  html += f"""
  var sections ={{{', '.join([f'{section.replace(f"$","").replace(" ","_")}: null' for section in figs.keys()]) }}};
"""
  html += """
  var lockzoom = null;

  function download(filename, text) {
    var element = document.createElement('a');
    element.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(JSON.stringify(text)));
    element.setAttribute('download', filename);

    element.style.display = 'none';
    document.body.appendChild(element);

    element.click();

    document.body.removeChild(element);
  }

  function download_data(filename) {
    let data = {};
    plots.slice(1, -1).each((i,div) => {
      let title  = div.layout.title.text.match("<b>(.*)</b>")[1];
      let graph  = (({ x, y, z }) => ({ x, y, z }))(div.data[2]);
      data[title] = graph
    });
    download(filename,data)
  }

  function relayout(ed, divs, axn_from, axn_to) {
    if (Object.entries(ed).length == 0) {return;}
    divs.each((index, elem) => {
      let x = elem.layout.xaxis;
      let y = elem.layout.yaxis4;
      var update = {};
      if (typeof axn_from === 'undefined') { axn_from = "3" }
      if (typeof axn_to === 'undefined') { axn_to = "3" }
      if (`xaxis${axn_from}.autorange` in ed && ed[`xaxis${axn_from}.autorange`] != x.autorange) {
        update[`xaxis${axn_to}.autorange`]= ed[`xaxis${axn_from}.autorange`];
      }
      if (`yaxis${axn_from}.autorange` in ed && ed[`yaxis${axn_from}.autorange`] != y.autorange) {
        update[`yaxis${axn_to}.autorange`] = ed[`yaxis${axn_from}.autorange`];
      }
      if (`xaxis${axn_from}.range` in ed && ed[`xaxis${axn_from}.range`] != x.range) {
        update[`xaxis${axn_to}.range`] = ed[`xaxis${axn_from}.range`];
      }
      if (`yaxis${axn_from}.range` in ed && ed[`yaxis${axn_from}.range`] != y.range) {
        update[`yaxis${axn_to}.range`] = ed[`yaxis${axn_from}.range`];
      }
      if (`xaxis${axn_from}.range[0]` in ed && ed[`xaxis${axn_from}.range[0]`] != x.range[0]) {
        update[`xaxis${axn_to}.range[0]`] = ed[`xaxis${axn_from}.range[0]`];
      }
      if (`xaxis${axn_from}.range[1]` in ed && ed[`xaxis${axn_from}.range[1]`] != x.range[1]) {
        update[`xaxis${axn_to}.range[1]`] = ed[`xaxis${axn_from}.range[1]`];
      }
      if (`yaxis${axn_from}.range[0]` in ed && ed[`yaxis${axn_from}.range[0]`] != y.range[0]) {
        update[`yaxis${axn_to}.range[0]`] = ed[`yaxis${axn_from}.range[0]`];
      }
      if (`yaxis${axn_from}.range[1]` in ed && ed[`yaxis${axn_from}.range[1]`] != y.range[1]) {
        update[`yaxis${axn_to}.range[1]`] = ed[`yaxis${axn_from}.range[1]`];
      }
      Plotly.update(elem, {}, update);
    });
  }

  function update_layout(ed, element) {
    if (lockzoom.is(':checked')) {
      relayout(ed, element);
    }
  }

  function timeline_sync_zoom(ed) {
    if (lockzoom.is(':checked')) {
      relayout(ed, $(overview), "", "2");

      relayout(ed, time_plots, "", "3");
    }
  }

  function init() {
    wsize = window.innerWidth;
    // Set navmenu size
    var nav = document.getElementById("navmenu");
    var newheight = window.innerHeight - document.getElementById("navbar").offsetHeight - 32;
    nav.style.height = `${newheight}px`;

    // Getting all plotly graphs
    plots = $('.plotly-graph-div');
    // Getting all plotly graphs that has time as abscissa 
    time_plots = $('div[id$="_time_plot"]'); // jQuery object
    // First one is overview figure
    overview = $('#overview_plot').get(0); // plots.get(0); // Needs to be the element, not jquery
    // Last one is timeline
    timeline = $('#timeline_plot').get(0); // plots.get(-1); // Needs to be the element, not jquery
    // Getting all graphs per section
    for (const [key, value] of Object.entries(sections)) {
      sections[key] = $(`div[id^="${key}_"]`);
    }
    lockzoom_div = $('.lockzoom');
    lockzoom = $('input[id="lockzoom"]');

    document.getElementById("toggle-menu").addEventListener('change', function() {
      plots.each((i,div) => {
        Plotly.Plots.resize(div);
      });
    });

    // "Snake" progress bar, obtained from: https://lab.hakim.se/progress-nav
    var toc = document.querySelector( '.section-toc' );
    var tocPath = document.querySelector( '.section-toc-marker path' );
    var tocItems;
    // Factor of screen size that the element must cross
    // before it's considered visible
    var TOP_MARGIN = 0.01,
      BOTTOM_MARGIN = 0.0;
    var pathLength;
    var lastPathStart,
      lastPathEnd;
    window.addEventListener( 'resize', drawPath, false );
    window.addEventListener( 'scroll', sync, false );

    drawPath();

    function drawPath() {
      tocItems = [].slice.call( toc.querySelectorAll( 'li' ) );
      // Cache element references and measurements
      tocItems = tocItems.map( function( item ) {
        var anchor = item.querySelector( 'a' );
        var target = document.getElementById( anchor.getAttribute( 'href' ).match(/\'(.*)\'/)[1] );
        return {
          listItem: item,
          anchor: anchor,
          target: target
        };
      } );

      // Remove missing targets
      tocItems = tocItems.filter( function( item ) {
        return !!item.target;
      } );

      var path = [];
      var pathIndent;
      tocItems.forEach( function( item, i ) {
        var x = item.anchor.offsetLeft - 5,
          y = item.anchor.offsetTop,
          height = item.anchor.offsetHeight;
        if( i === 0 ) {
          path.push( 'M', x, y, 'L', x, y + height );
          item.pathStart = 0;
        }
        else {
          // Draw an additional line when there's a change in
          // indent levels
          if( pathIndent !== x ) path.push( 'L', pathIndent, y );
          path.push( 'L', x, y );
          // Set the current path so that we can measure it
          tocPath.setAttribute( 'd', path.join( ' ' ) );
          item.pathStart = tocPath.getTotalLength() || 0;
          path.push( 'L', x, y + height );
        }
        pathIndent = x;
        tocPath.setAttribute( 'd', path.join( ' ' ) );
        item.pathEnd = tocPath.getTotalLength();
      } );
      pathLength = tocPath.getTotalLength();
      sync();
    }

    function sync() {
      var windowHeight = window.innerHeight;
      var pathStart = pathLength,
        pathEnd = 0;
      var visibleItems = 0;

      tocItems.forEach( function( item ) {
        var targetBounds = item.target.getBoundingClientRect();
        if( targetBounds.bottom > windowHeight * TOP_MARGIN && targetBounds.top < windowHeight * ( 1 - BOTTOM_MARGIN ) ) {
          pathStart = Math.min( item.pathStart, pathStart );
          pathEnd = Math.max( item.pathEnd, pathEnd );
          visibleItems += 1;
          item.listItem.classList.add( 'visible' );
        }
        else {
          item.listItem.classList.remove( 'visible' );
        }
      } );

      // Specify the visible path or hide the path altogether
      // if there are no visible items
      if( visibleItems > 0 && pathStart < pathEnd ) {
        if( pathStart !== lastPathStart || pathEnd !== lastPathEnd ) {
          tocPath.setAttribute( 'stroke-dashoffset', '1' );
          tocPath.setAttribute( 'stroke-dasharray', '1, '+ pathStart +', '+ ( pathEnd - pathStart ) +', ' + pathLength );
          tocPath.setAttribute( 'opacity', 1 );
        }
      }
      else {
        tocPath.setAttribute( 'opacity', 0 );
      }
      lastPathStart = pathStart;
      lastPathEnd = pathEnd;
    }

    /* Timeline click event */
    if (timeline) {
      timeline.on("plotly_click", function(ed) { 
        /* Relayout timeline when clicked on a bar  */
        Plotly.relayout(timeline, { "xaxis.range[0]": ed.points[0].base, "xaxis.range[1]": ed.points[0].value });
      });
    }

    lockzoom_div.css('visibility', 'visible');

    // Synchronize zoom between plots
    lockzoom.change( function() {
      if ($(this).is(':checked')) {
        sync_zoom()
      } 
    });
  }

  // Add scroll event listener to add fragment of current block on URL
  window.addEventListener( 'scroll', function () {
    if (!catch_scroll) {return;}
    let graphs = Array.from(document.querySelectorAll('.block'))
    let visible = graphs.find((el)=>{return isElementInViewport(el);});
    if (visible) {
      let hash = $(visible).attr('id');
      if (currentHash == hash) {return;}
      // window.location.hash = hash;
      // if(history.pushState) { history.pushState(null, null, "#"+hash); } else { window.location.hash = hash; } 
      history.replaceState(null, null, "#"+hash);
      currentHash = hash;
    }
  }, false );

  // Getting initial position from URL and scrolling to it, if present
  var currentHash = window.location.hash.substring(1);
  if (currentHash) scrollIntoView(currentHash);

  // Check if element 'el' is visible in viewport
  function isElementInViewport (el) {
    if (typeof jQuery === "function" && el instanceof jQuery) {
        el = el[0];
    }
    var rect = el.getBoundingClientRect();
    // Added small value above the top, otherwise it was changing the fragment to the graph below
    return ( rect.top > -3 && rect.top <= (window.innerHeight || document.documentElement.clientHeight) );
  }

  // Scroll to given '#elementid' when it is ready in page. If not present yet, try every second, waiting for it to be ready
  function scrollIntoView(elementid) {
    if(repeat) clearInterval(repeat); // Stopping previous checks
    catch_scroll = false;
    let element = document.getElementById(elementid);
    // If element is ready, scroll imediately
    if (element) {
      waitForElement(element).then(function(){
        element.scrollIntoView({behavior: "instant"});
      });
      catch_scroll = true;
      return;
    }
    // Otherwise, check every second
    repeat = window.setInterval(function() {
      element = document.getElementById(elementid);
      if (element) {
        waitForElement(element).then(function(){
          element.scrollIntoView({behavior: "instant"});
        });
        catch_scroll = true;
        clearInterval(repeat);
      }
    }, 1000)
  }

  // Activating synchronisation of zoom between graphs within a section
  // and timeline zoom synchronisation
  function sync_zoom() {
    for (const [key, value] of Object.entries(sections)) {
      if (value) {
        for (const el of value) {
          el.on( "plotly_relayout", function(ed) { update_layout(ed, value.not(el)); } );
        }
      }
    }
    
    if (timeline) {
      timeline.on("plotly_relayout", function(ed) { timeline_sync_zoom(ed); });
    }
  }

  /**
   * Wait for an element before resolving a promise
   * Adapted from https://stackoverflow.com/a/34863951/3142385
   * @param {Node} element - element to wait for
   * @param {Integer} timeout - Milliseconds to wait before timing out, or 0 for no timeout
   */
  function waitForElement(element, timeout){
    return new Promise((resolve, reject)=>{
      var timer = false;
      if(!!element) return resolve();
      const observer = new MutationObserver(()=>{
        if(!!element) {
          observer.disconnect();
          if(timer !== false) clearTimeout(timer);
          return resolve();
        }
      });
      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
      if(timeout) timer = setTimeout(()=>{
        observer.disconnect();
        reject();
      }, timeout);
    });
  }

  window.addEventListener('load', init);

  /* Check window size to toggle menu and adapt its height */
  function onresize(e) {
    height = e.target.innerHeight;
    width = e.target.innerWidth;
    if (width == wsize) { return; }
    if (width < 1000)  {
      document.getElementById("toggle-menu").checked = true; 
    } else { 
      document.getElementById("toggle-menu").checked = false;
    }
    wsize = width;
    var nav = document.getElementById("navmenu");
    var newheight = height - document.getElementById("navbar").offsetHeight - 32;
    nav.style.height = `${newheight}px`;
  }
  window.addEventListener("resize", onresize);

  </script>
"""

  # Getting location of plotly
  if loc := config['appearance'].get('plotly_location'):
      plotly_path = loc
  else:
    plotly_path = f"{replace_vars(config['appearance']['hostname'], config['appearance'])}/js/ext/plotly.min.js"
  # Getting location of jquery
  if loc := config['appearance'].get('jquery_location'):
      jquery_path = loc
  else:
    jquery_path = f"{replace_vars(config['appearance']['hostname'], config['appearance'])}/js/ext/jquery.min.js"

  html += f"  <script src='{jquery_path}'></script>\n"
  html += f"  <script src='{plotly_path}'></script>\n"

  html += f"""
  <title>Job ID {config['appearance']['jobid']} Report</title>
  </head>
  <body>
  <header>
"""
  html += navbar
  html += """
  </header>

  <input class="toggle-menu" id="toggle-menu" type="checkbox" />
  <label for="toggle-menu" class="menu-button no-print"></label>

  <script type="text/javascript">
    /* Setting checkbox initial value */
    if (window.matchMedia("(max-width: 1000px)").matches) {
    document.getElementById("toggle-menu").checked = true;
    } else {
      document.getElementById("toggle-menu").checked = false;
    }
  </script>

  <main>
"""
  # TOC:
  html += f"""
  <nav id="navmenu" class="section-toc no-print">
    <ul>
    <li><a href="javascript:scrollIntoView('report')"><b>Job {config['appearance']['jobid']} Report</b></a></li>
"""
  if overview: html += '<li><a href="javascript:scrollIntoView(\'overview\')">Job-Usage Overview</a></li>\n'
  for systype, section in figs.items():
    stype = systype.replace("$","").replace(" ","_")
    html += f'  <li><a href="javascript:scrollIntoView(\'{stype}\')">{systype}</a>\n'
    html += f'  <ul>\n'
    for title in section.keys():
      html += '    <li><a href="javascript:scrollIntoView(\'{}_{}\')">{}</a></li>\n '.format(stype,title.replace(" ","_"),title)
    html += f'  </ul>\n'
    html += f'  </li>\n'
  if nodelist: html += '<li><a href="javascript:scrollIntoView(\'nodelist\')">Node List</a></li>\n'
  if timeline: html += '<li><a href="javascript:scrollIntoView(\'timeline\')">Timeline</a></li>\n'
  if config['error']: html += '<li><a href="javascript:scrollIntoView(\'system_report\')">System Error Report</a></li>\n'
  html += """
  </ul>
  <svg class="section-toc-marker" width="200" height="200">
    <path stroke="#444" stroke-width="3" fill="transparent" stroke-dasharray="0, 0, 0, 1000" stroke-linecap="round" stroke-linejoin="round" transform="translate(-0.5, -0.5)" d=""/>
  </svg>
  </nav>
"""

  # Start of second grid column
  html += "  <div>\n"

  # First page tables:
  html += f"""<section class="block" id="report">
  {first}
  </section>
"""

  # Overview figure:
  if overview:
    html += f"""
    <section class="block" id="overview" style="margin-top:50px;">
"""
    copy_link = { 'name': 'Copy link to this graph',
                    'icon': { 'width': 1634,
                              'height': 1634,
                              'path': 'M 1441 434 q 0 40 -28 68 l -208 208 q -28 28 -68 28 q -42 0 -72 -32 q 3 -3 19 -18.5 t 21.5 -21.5 t 15 -19 t 13 -25.5 t 3.5 -27.5 q 0 -40 -28 -68 t -68 -28 q -15 0 -27.5 3.5 t -25.5 13 t -19 15 t -21.5 21.5 t -18.5 19 q -33 -31 -33 -73 q 0 -40 28 -68 l 206 -207 q 27 -27 68 -27 q 40 0 68 26 l 147 146 q 28 28 28 67 z M 738 1139 q 0 40 -28 68 l -206 207 q -28 28 -68 28 q -39 0 -68 -27 l -147 -146 q -28 -28 -28 -67 q 0 -40 28 -68 l 208 -208 q 27 -27 68 -27 q 42 0 72 31 q -3 3 -19 18.5 t -21.5 21.5 t -15 19 t -13 25.5 t -3.5 27.5 q 0 40 28 68 t 68 28 q 15 0 27.5 -3.5 t 25.5 -13 t 19 -15 t 21.5 -21.5 t 18.5 -19 q 33 31 33 73 z M 1633 434 q 0 -120 -85 -203 l -147 -146 q -83 -83 -203 -83 q -121 0 -204 85 l -206 207 q -83 83 -83 203 q 0 123 88 209 l -88 88 q -86 -88 -208 -88 q -120 0 -204 84 l -208 208 q -84 84 -84 204 t 85 203 l 147 146 q 83 83 203 83 q 121 0 204 -85 l 206 -207 q 83 -83 83 -203 q 0 -123 -88 -209 l 88 -88 q 86 88 208 88 q 120 0 204 -84 l 208 -208 q 84 -84 84 -204 z',
                          },
                    'attr': 'help',
                    'click': "function() { navigator.clipboard.writeText(`${window.location.href.split('#')[0]}#overview`);}" ,
                    }
    help_button = { 'name': '1-min average CPU and GPU usage, averaged over all the nodes/GPUs',
                    'icon': { 'width': 512,
                              'height': 512,
                              'path': 'M256 0C114.6 0 0 114.6 0 256s114.6 256 256 256s256-114.6 256-256S397.4 0 256 0zM256 464c-114.7 0-208-93.31-208-208S141.3 48 256 48s208 93.31 208 208S370.7 464 256 464zM256 336c-18 0-32 14-32 32s13.1 32 32 32c17.1 0 32-14 32-32S273.1 336 256 336zM289.1 128h-51.1C199 128 168 159 168 198c0 13 11 24 24 24s24-11 24-24C216 186 225.1 176 237.1 176h51.1C301.1 176 312 186 312 198c0 8-4 14.1-11 18.1L244 251C236 256 232 264 232 272V288c0 13 11 24 24 24S280 301 280 288V286l45.1-28c21-13 34-36 34-60C360 159 329 128 289.1 128z',
                          },
                    'attr': 'help',
                    'click': "function() { window.open('https://apps.fz-juelich.de/jsc/llview/docu/jobreport/metrics_list/', '_blank').focus();}" ,
                    }
    datafile=f"{config['appearance']['system']}-{config['appearance']['jobid']}-overview.json"
    download_data_button = {'name': 'Download data',
                            'icon': { 'width': 514,
                                      'height': 514,
                                      'path': 'M216 0h80c13.3 0 24 10.7 24 24v168h87.7c17.8 0 26.7 21.5 14.1 34.1L269.7 378.3c-7.5 7.5-19.8 7.5-27.3 0L90.1 226.1c-12.6-12.6-3.7-34.1 14.1-34.1H192V24c0-13.3 10.7-24 24-24zm296 376v112c0 13.3-10.7 24-24 24H24c-13.3 0-24-10.7-24-24V376c0-13.3 10.7-24 24-24h146.7l49 49c20.1 20.1 52.5 20.1 72.6 0l49-49H488c13.3 0 24 10.7 24 24zm-124 88c0-11-9-20-20-20s-20 9-20 20 9 20 20 20 20-9 20-20zm64 0c0-11-9-20-20-20s-20 9-20 20 9 20 20 20 20-9 20-20z',
                                  },
                            'attr': 'download',
                            'click': "function(gd) { download('"+datafile+"', [(({ name, x, y }) => ({ name, x, y }))(gd.data[1]), (({ name, x, y }) => ({ name, x, y }))(gd.data[3])] );}" ,
                            }
    html += overview.to_html( include_plotlyjs=False,
                              full_html=False,
                              config={'displaylogo': False,
                                      # 'displayModeBar': True,
                                      'modeBarButtons': [ [copy_link, help_button, "zoom2d", "pan2d", "zoomIn2d", "zoomOut2d", "resetScale2d",download_data_button] ],
                                      },
                              div_id='overview_plot').replace('"function','function').replace(';}"}','; }}') #.replace('"function(gd)','function(gd)').replace('(gd.data[3])] );}"','(gd.data[3])] );}')
    html += f"""
    </section>
"""

  # Plots
  for systype, section in figs.items():
    stype = systype.replace("$","").replace(" ","_")
    html += f"""
    <hr class="no-print">
    <section id="{stype}"> </section>
"""
    for title, graph in section.items():
      id = f"{stype}_{title.replace(' ','_')}"
      html += f"""
      <section class="block" id="{id}">
"""
      copy_link = { 'name': 'Copy link to this graph',
                      'icon': { 'width': 1634,
                                'height': 1634,
                                'path': 'M 1441 434 q 0 40 -28 68 l -208 208 q -28 28 -68 28 q -42 0 -72 -32 q 3 -3 19 -18.5 t 21.5 -21.5 t 15 -19 t 13 -25.5 t 3.5 -27.5 q 0 -40 -28 -68 t -68 -28 q -15 0 -27.5 3.5 t -25.5 13 t -19 15 t -21.5 21.5 t -18.5 19 q -33 -31 -33 -73 q 0 -40 28 -68 l 206 -207 q 27 -27 68 -27 q 40 0 68 26 l 147 146 q 28 28 28 67 z M 738 1139 q 0 40 -28 68 l -206 207 q -28 28 -68 28 q -39 0 -68 -27 l -147 -146 q -28 -28 -28 -67 q 0 -40 28 -68 l 208 -208 q 27 -27 68 -27 q 42 0 72 31 q -3 3 -19 18.5 t -21.5 21.5 t -15 19 t -13 25.5 t -3.5 27.5 q 0 40 28 68 t 68 28 q 15 0 27.5 -3.5 t 25.5 -13 t 19 -15 t 21.5 -21.5 t 18.5 -19 q 33 31 33 73 z M 1633 434 q 0 -120 -85 -203 l -147 -146 q -83 -83 -203 -83 q -121 0 -204 85 l -206 207 q -83 83 -83 203 q 0 123 88 209 l -88 88 q -86 -88 -208 -88 q -120 0 -204 84 l -208 208 q -84 84 -84 204 t 85 203 l 147 146 q 83 83 203 83 q 121 0 204 -85 l 206 -207 q 83 -83 83 -203 q 0 -123 -88 -209 l 88 -88 q 86 88 208 88 q 120 0 204 -84 l 208 -208 q 84 -84 84 -204 z',
                            },
                      'attr': 'help',
                      'click': f"function() {{ navigator.clipboard.writeText(`${{window.location.href.split('#')[0]}}#{id}`);}}" ,
                      }
      help_button = { 'name': config['plots'][systype.replace("$",r"\$")][title]['description'],
                      'icon': { 'width': 512,
                                'height': 512,
                                'path': 'M256 0C114.6 0 0 114.6 0 256s114.6 256 256 256s256-114.6 256-256S397.4 0 256 0zM256 464c-114.7 0-208-93.31-208-208S141.3 48 256 48s208 93.31 208 208S370.7 464 256 464zM256 336c-18 0-32 14-32 32s13.1 32 32 32c17.1 0 32-14 32-32S273.1 336 256 336zM289.1 128h-51.1C199 128 168 159 168 198c0 13 11 24 24 24s24-11 24-24C216 186 225.1 176 237.1 176h51.1C301.1 176 312 186 312 198c0 8-4 14.1-11 18.1L244 251C236 256 232 264 232 272V288c0 13 11 24 24 24S280 301 280 288V286l45.1-28c21-13 34-36 34-60C360 159 329 128 289.1 128z',
                            },
                      'attr': 'help',
                      'click': "function() { window.open('https://apps.fz-juelich.de/jsc/llview/docu/jobreport/metrics_list/', '_blank').focus();}" ,
                      }

      datafile=f"{config['appearance']['system']}-{config['appearance']['jobid']}-{id.lower()}.json"
      download_data_button = {'name': 'Download data',
                              'icon': { 'width': 514,
                                        'height': 514,
                                        'path': 'M216 0h80c13.3 0 24 10.7 24 24v168h87.7c17.8 0 26.7 21.5 14.1 34.1L269.7 378.3c-7.5 7.5-19.8 7.5-27.3 0L90.1 226.1c-12.6-12.6-3.7-34.1 14.1-34.1H192V24c0-13.3 10.7-24 24-24zm296 376v112c0 13.3-10.7 24-24 24H24c-13.3 0-24-10.7-24-24V376c0-13.3 10.7-24 24-24h146.7l49 49c20.1 20.1 52.5 20.1 72.6 0l49-49H488c13.3 0 24 10.7 24 24zm-124 88c0-11-9-20-20-20s-20 9-20 20 9 20 20 20 20-9 20-20zm64 0c0-11-9-20-20-20s-20 9-20 20 9 20 20 20 20-9 20-20z',
                                    },
                              'attr': 'download',
                              'click': "function(gd) { download('"+datafile+"', [(({ name, x, y, z }) => ({ name, x, y, z }))(gd.data[2])] );}" ,
                              }
      html += graph['graph'].to_html( include_plotlyjs=False,
                                      full_html=False,
                                      config={'displaylogo': False,
                                              # 'displayModeBar': True,
                                              'modeBarButtons': [ [copy_link, help_button, "zoom2d", "pan2d", "zoomIn2d", "zoomOut2d", "resetScale2d",download_data_button] ],
                                              },
                                      div_id=id+('_time_plot' if graph['x']=='ts' else '_plot')).replace('"function','function').replace(';}"}','; }}')
      html += f"""
      </section>
"""

  # Nodelist
  if nodelist:
    html += f"""
    <hr class="no-print">
    <section class="block" id="nodelist">
    <h2>Node List</h2>
    {nodelist}
    </section>
"""

  # Timeline:
  if timeline:
    html += f"""
    <hr class="no-print">
    <section class="block" id="timeline" style="margin-top:50px;">
"""
    copy_link = { 'name': 'Copy link to this graph',
                    'icon': { 'width': 1634,
                              'height': 1634,
                              'path': 'M 1441 434 q 0 40 -28 68 l -208 208 q -28 28 -68 28 q -42 0 -72 -32 q 3 -3 19 -18.5 t 21.5 -21.5 t 15 -19 t 13 -25.5 t 3.5 -27.5 q 0 -40 -28 -68 t -68 -28 q -15 0 -27.5 3.5 t -25.5 13 t -19 15 t -21.5 21.5 t -18.5 19 q -33 -31 -33 -73 q 0 -40 28 -68 l 206 -207 q 27 -27 68 -27 q 40 0 68 26 l 147 146 q 28 28 28 67 z M 738 1139 q 0 40 -28 68 l -206 207 q -28 28 -68 28 q -39 0 -68 -27 l -147 -146 q -28 -28 -28 -67 q 0 -40 28 -68 l 208 -208 q 27 -27 68 -27 q 42 0 72 31 q -3 3 -19 18.5 t -21.5 21.5 t -15 19 t -13 25.5 t -3.5 27.5 q 0 40 28 68 t 68 28 q 15 0 27.5 -3.5 t 25.5 -13 t 19 -15 t 21.5 -21.5 t 18.5 -19 q 33 31 33 73 z M 1633 434 q 0 -120 -85 -203 l -147 -146 q -83 -83 -203 -83 q -121 0 -204 85 l -206 207 q -83 83 -83 203 q 0 123 88 209 l -88 88 q -86 -88 -208 -88 q -120 0 -204 84 l -208 208 q -84 84 -84 204 t 85 203 l 147 146 q 83 83 203 83 q 121 0 204 -85 l 206 -207 q 83 -83 83 -203 q 0 -123 -88 -209 l 88 -88 q 86 88 208 88 q 120 0 204 -84 l 208 -208 q 84 -84 84 -204 z',
                          },
                    'attr': 'help',
                    'click': "function() { navigator.clipboard.writeText(`${window.location.href.split('#')[0]}#timeline`);}" ,
                    }
    help_button = { 'name': 'Timeline containing all the steps in a job. A step can be clicked to focus. When zoom-lock is selected, syncs zoom between all graphs.',
                    'icon': { 'width': 512,
                              'height': 512,
                              'path': 'M256 0C114.6 0 0 114.6 0 256s114.6 256 256 256s256-114.6 256-256S397.4 0 256 0zM256 464c-114.7 0-208-93.31-208-208S141.3 48 256 48s208 93.31 208 208S370.7 464 256 464zM256 336c-18 0-32 14-32 32s13.1 32 32 32c17.1 0 32-14 32-32S273.1 336 256 336zM289.1 128h-51.1C199 128 168 159 168 198c0 13 11 24 24 24s24-11 24-24C216 186 225.1 176 237.1 176h51.1C301.1 176 312 186 312 198c0 8-4 14.1-11 18.1L244 251C236 256 232 264 232 272V288c0 13 11 24 24 24S280 301 280 288V286l45.1-28c21-13 34-36 34-60C360 159 329 128 289.1 128z',
                          },
                    'attr': 'help',
                    'click': "function() { window.open('https://apps.fz-juelich.de/jsc/llview/docu/jobreport/metrics_list/', '_blank').focus();}" ,
                    }
    datafile=f"{config['appearance']['system']}-{config['appearance']['jobid']}-timeline.json"
    download_data_button = {'name': 'Download data',
                            'icon': { 'width': 514,
                                      'height': 514,
                                      'path': 'M216 0h80c13.3 0 24 10.7 24 24v168h87.7c17.8 0 26.7 21.5 14.1 34.1L269.7 378.3c-7.5 7.5-19.8 7.5-27.3 0L90.1 226.1c-12.6-12.6-3.7-34.1 14.1-34.1H192V24c0-13.3 10.7-24 24-24zm296 376v112c0 13.3-10.7 24-24 24H24c-13.3 0-24-10.7-24-24V376c0-13.3 10.7-24 24-24h146.7l49 49c20.1 20.1 52.5 20.1 72.6 0l49-49H488c13.3 0 24 10.7 24 24zm-124 88c0-11-9-20-20-20s-20 9-20 20 9 20 20 20 20-9 20-20zm64 0c0-11-9-20-20-20s-20 9-20 20 9 20 20 20 20-9 20-20z',
                                  },
                            'attr': 'download',
                            'click': "function(gd) { download('"+datafile+"', gd.data[0].x.map((_, i) => ({ start_time: gd.data[0].base[i], duration: gd.data[0].x[i], step: gd.data[0].y[i], info: gd.data[0].hovertext[i] })) );}",
                            }

    html += timeline.to_html( include_plotlyjs=False,
                              full_html=False,
                              config={'displaylogo': False,
                                      # 'displayModeBar': True,
                                      'modeBarButtons': [ [copy_link, help_button, "zoom2d", "pan2d", "zoomIn2d", "zoomOut2d", "resetScale2d", download_data_button] ],
                                      },
                              div_id='timeline_plot').replace('"function','function').replace(';}"}','; }}') #.replace('"function(gd)','function(gd)').replace('(gd.data[3])] );}"','(gd.data[3])] );}')
    html += f"""
    </section>
"""

  # System Error Report
  if system_report:
    html += f"""
    <hr class="no-print">
    <section class="block" id="system_report">
    <h2>System Error Report</h2>
    {system_report}
    </section>
"""
  html +="</div>"

  # Closing HTML
  html += """
  </main>
  </body>
  </html>
"""


  # Writing to file
  if config['html']:
    with open(filename, 'w') as f:
      f.write(html)
  if config['gzip']:
    import gzip
    with gzip.open(f"{filename}.gz", 'wb') as f:
      f.write(html.encode())
  return

def CreateNodelist(config,gpus,nl_config,nodedict,error_nodes):
  nodelist = ""
  numgpu = 0
  for idx,(node, specs) in enumerate(nodedict.items()):
    try:
      ic = list(specs['IC'].keys())[0]
      color = list(specs['IC'].values())[0]
      color = list(255*x for x in color)
    except KeyError:
      ic = '-'
      color = [0.0,0.0,0.0]
    nodelist += f"""
    <div class="{'errornode' if node in error_nodes else 'node'}" style="background-color: rgb{tuple(color+[0.1])};">
      <div style="text-align: center;">
      <span style="float: left; color: dimgray; padding: 0px 5px 0px 5px;">{idx+1}</span>
      <b>{node}</b>
      </div>
"""
    if gpus:
      for gpu, spec in specs.items():
        if 'GPU' not in gpu: continue
        numgpu += 1
        nodelist += f"""
          <div style="text-align: center; font-size: 8pt;">
          <span style="float:left; color: dimgray; padding: 0px 5px 0px 0px;">{numgpu}</span>
          <b>{gpu}: </b>{spec}
          </div>
"""

    nodelist += f"""
      <div style="text-align: center; font-size: 10pt; color: rgb{tuple(color)};">
      Interconnect group: {ic}
      </div>
    </div>
"""
  return nodelist

def CreateSystemErrorReport(error_lines,data):
  system_report_html = f"""
  <div style="position: relative; padding: 10px 10px 10px 10px; margin: 10px 0px 10px 0px; text-align: left; border: 2px solid black;">
  <div style="padding: 15px 0px 0px 150px;"># Msgs: <span style="color: red; padding-right: 50px"><b>{data['rc']['nummsgs']}</b></span> # Nodes: <span style="color: red;"><b>{data['rc']['numerrnodes']}</b></span></div>
  <div style="padding: 20px 0px 0px 50px; font-style: italic;">Error Messages: </div>
  <p style="font-family: 'Liberation Mono', 'Courier New';">
"""
  for errorline in error_lines:
    system_report_html += f"""
    {errorline}<br />
"""
  system_report_html += """
  </p>
  </div>
"""
  return system_report_html

def CreateFirstTables(data,config,num_cpus,num_gpus,gpus,ierr):
  tables = f"""
  <h1>{data['job']['system'].upper().replace('_',' ')} Job Report</h1>
  <br />
  <table style="border-bottom: 1px solid black; width:100%;">
  <tr>
    <td>Job ID: <b>{data["job"]["jobid"]}</b></td>
    <td>User: <b>{data["job"]["owner"]}</b></td>
    <td>Project: <b>{data['job']['account']}</b></td>
    <td>Job Name: <b>{data['job']['name']}</b></td>
  </tr>
  </table>

  <table style="border-top: 1px solid black; border-bottom: 1px solid black; width:100%;">
  <tr>
    <td ><b><i>Runtime: </i>{data['job']['runtimehm']}</b> </td>
    <td colspan="2" class="rborder">&rarr; {data['job']['runtimeperc']}% of Wall: {data['job']['wallhm']} </td>
    <td><b>Job Performance Metrics</b></td>
    <td style="text-align: center;">Min.</td>
    <td style="text-align: center;">Avg.</td>
    <td style="text-align: center;">Max.</td>
    <td></td>
  </tr>
  <tr>
    <td>Submit Time: </td>
    <td colspan="2" class="rborder"><b>{data["job"]["queuedate"]}</b></td>
    <td>CPU Usage: </td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['usage_min'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['usage_avg'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['usage_max'],"2f")}</b></td>
    <td> %</td>
  </tr>
  <tr>
    <td>Start Time: </td>
    <td colspan="2" class="rborder"><b>{data["job"]["starttime"]}</b> ({data['job']['waittime'].strip()} in queue)</td>
    <td>CPU Load: </td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['load_min'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['load_avg'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['load_max'],"2f")}</b></td>
    <td></td>
  </tr>
  <tr>
"""
  if config['finished']:
    tables += f"""
      <td>End Time: </td>
      <td colspan="2" class="rborder"><b>{data["job"]["updatetime"]}</b> </td>  
"""
  else:
    tables += f"""
      <td> </td>
      <td colspan="2" class="rborder" style="color:DarkGoldenRod;"> (Running)</td>  
"""

  tables += f"""
    <td>CPU Memory: </td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['used_mem_min'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['used_mem_avg'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['cpu']['used_mem_max'],"2f")}</b></td>
    <td>MiB</td>
  </tr>
  <tr>
    <td>Last Update: </td>
    <td colspan="2" class="rborder"> <b>{data["job"]["lastupdate"]}</b></td>  
    <td>Interconnect Traffic (in): </td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['mbin_min'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['mbin_avg'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['mbin_max'],"2f")}</b></td>
    <td>MiB/s</td>
  </tr>
  <tr>
    <td class="bborder">Estimated End Time: </td>
    <td colspan="2" class="bborder rborder">{data["job"]["estendtime"]}</td>
    <td>Interconnect Traffic (out): </td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['mbout_min'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['mbout_avg'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['mbout_max'],"2f")}</b></td>
    <td>MiB/s</td>
  </tr>
  <tr>
    <td>Queue: </td>
    <td colspan="2" class="rborder"><b>{data["job"]["queue"]}</b></td>
    <td>Interconnect Packets (in): </td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['pckin_min'],"0f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['pckin_avg'],"0f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['pckin_max'],"0f")}</b></td>
    <td>pck/s</td>
  </tr>
  <tr>
    <td>Job Size, #Nodes: </td>
    <td><b>{num_cpus}</b></td>
    <td class="rborder"><span style="font-size:10pt">#Data Points: {data["num_datapoints"]["ld_ndps"]}</span></td>
    <td>Interconnect Packets (out): </td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['pckout_min'],"0f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['pckout_avg'],"0f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['fabric']['pckout_max'],"0f")}</b></td>
    <td>pck/s</td>
  </tr>
  <tr>
"""
  if gpus:
    tables += f"""
    <td>Job Size, #GPUs: </td>
    <td><b>{num_gpus}</b></td>
    <td class="rborder"><span style="font-size:10pt">#Data Points: {data["num_datapoints"]["gpu_ndps"]}</span></td>
"""
  else:
    tables += f"""
    <td colspan="3" class="rborder"></td>
"""
  tables += f"""
    <td>Node Power: </td>
    <td style="text-align: right;"><b>{format_float_string(data['energy']['pwr_nd_min'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['energy']['pwr_nd_avg'],"2f")}</b></td>
    <td style="text-align: right;"><b>{format_float_string(data['energy']['pwr_nd_max'],"2f")}</b></td>
    <td>W</td>
  </tr>
  </table>
  <table style="border-top: 1px solid black; border-bottom: 1px solid black; width:100%;">
    <tr>
    {"<td><b>Interactive Job</b></td>" if data['job']['command']=="(null)" else "<td style='width: 15em'>Submission Script:</td><td><b>"+data['job']['command']+"</b></td>"}
    </tr>
  </table>
  <table style="border-top: 1px solid black; border-bottom: 1px solid black; width:100%;">
  <tr>
    <td><b>Job I/O Statistics</b></td>
    <td colspan="2">Total Data Write</td>
    <td colspan="2">Total Data Read</td>
    <td colspan="2">Max. Data Rate/Node Write</td>
    <td colspan="2">Max. Data Rate/Node Read</td>
    <td colspan="2">Max. Open-Close Rate/Node</td>
  </tr>
"""
  for fs in ['home','project','scratch','fastdata']:
    tables += f"""
    <tr>
      <td>${fs.upper()}: </td>
      <td style="text-align: right;"><b>{format_float_string(data['fs'][f'fs_{fs}_Mbw_sum'],"2f")}</b></td>  
      <td>MiB</td>
      <td style="text-align: right;"><b>{format_float_string(data['fs'][f'fs_{fs}_Mbr_sum'],"2f")}</b></td>  
      <td>MiB</td>
      <td style="text-align: right;"><b>{format_float_string(data['fs'][f'fs_{fs}_MbwR_max'],"2f")}</b></td>  
      <td>MiB/s</td>
      <td style="text-align: right;"><b>{format_float_string(data['fs'][f'fs_{fs}_MbrR_max'],"2f")}</b></td>  
      <td>MiB/s</td>
      <td style="text-align: right;"><b>{format_float_string(data['fs'][f'fs_{fs}_ocR_max'],"2f")}</b></td>  
      <td>op./s</td>
    </tr>
"""
  tables += f"""
  </table>
"""
  if gpus:
    tables += f"""
    <table style="border-top: 1px solid black; border-bottom: {"1px" if config['finished'] else "2px"} solid black; width:100%;">
    <tr>
      <td colspan="8"><b>Job GPU Statistics</b></td>
    </tr>
    <tr>
      <td style="text-align: right;">{data['gpu']['usage_or_util_text']}: </td>
      <td><b>{data['gpu']['usage_avg']:.2f}</b> %</td>
      <td style="text-align: right;">Avg. Mem. Usage Rate: </td>
      <td><b>{float(data['gpu']['gpu_memur_avg']):.2f}</b> %</td>
      <td style="text-align: right;">Avg. GPU Temp.: </td>
      <td><b>{float(data['gpu']['gpu_temp_avg']):.2f}</b> &deg;C</td>
      <td style="text-align: right;">Avg. GPU Power: </td>
      <td><b>{float(data['gpu']['gpu_pu_avg'])/1000.0:.2f}</b> W</td>
    </tr>
    <tr>
      <td style="text-align: right;">Max. Clk Stream/Mem: </td>
      <td><b>{float(data['gpu']['gpu_sclk_max']):.0f}/{float(data['gpu']['gpu_clk_max']):.0f}</b> MHz</td>
      <td style="text-align: right;">Max. Mem. Usage: </td>
      <td><b>{float(data['gpu']['gpu_memu_max'])/1024.0/1024.0:.2f}</b> MiB</td>
      <td style="text-align: right;">Max. GPU Temp.: </td>
      <td><b>{float(data['gpu']['gpu_temp_max']):.2f}</b> &deg;C</td>
      <td style="text-align: right;">Max. GPU Power: </td>
      <td><b>{float(data['gpu']['gpu_pu_max'])/1000.0:.2f}</b> W</td>
    </tr>
    </table>
"""
  if config['finished']:
    if (data['rc']['rc_state'] == "COMPLETED"):
      color = 'green'
    elif ('FAIL' in data['rc']['rc_state']):
      color = 'red'
    else:
      color = 'goldenrod'

    tables += f"""
    <table style="border-top: 1px solid black; width:100%;">
    <tr>
      <td><b>Job Finalization Report</b></td>
      <td colspan="2">Job State: <span style="color: {color}"><b>{data['rc']['rc_state']}</b></span></td>
      <td>Return Code: <span style="color: {color}"><b>{data['rc']['rc_rc']}</b></span></td>
      <td>Signal Number: <span style="color: {color}"><b>{data['rc']['rc_signr']}</b></span></td>
    </tr>
"""
    if ierr == 1:
      tables += f"""
      <tr>
        <td><b>System Error Report</b></td>
        <td># Msgs: <span style="color: red"><b>{data['rc']['nummsgs']}</b></span></td>
        <td># Nodes: <span style="color: red"><b>{data['rc']['numerrnodes']}</b></span></td>
        <td colspan="2"><div style='border-bottom: 2px dotted red;' class='tooltip'><a href="javascript:scrollIntoView('system_report')" style='color: red;'><b>{data['rc']['err_type'] if data['rc']['err_type'] else "(Details)"}</b></a><span style='width: 300px;' class='tooltiptextright'>Click for a detailed list of error messages</span></div></td>
      </tr>
"""
    tables += f"""
    <tr>
      <td colspan="5" style="text-align: center;">
      <b>This job has used approximately: {num_cpus} nodes &times; {config['system'][data['job']['system'].upper()][data["job"]["queue"]]['cores']} cores &times; {float(data['job']['runtime']):.3f} hours = {num_cpus*config['system'][data['job']['system'].upper()][data["job"]["queue"]]['cores']*float(data['job']['runtime']):.2f} core-h</b>
"""
    if config['energy']:
      tables += f"""
      <br />
      <b>Estimated energy used by this job, integrated from the node power snapshots: {data['energy']['en_nd_all_sum']:.2f} M-Joules = {data['energy']['en_nd_all_sum']*0.2778:.2f} kWh</b>
"""
    tables += f"""
      </td>
    </tr>
    </table>
"""
  else: # if job is still running:
    if data['job']['wallh'] != 'UNLIMITED':
      tables += f"""
      <div style="margin: 15px">
      <b>This job will use approximately {num_cpus} nodes &times; {config['system'][data['job']['system'].upper()][data["job"]["queue"]]['cores']} cores &times; {float(data['job']['wallh']):.3f} hours = {num_cpus*config['system'][data['job']['system'].upper()][data["job"]["queue"]]['cores']*float(data['job']['wallh']):.2f} core-h for the specified walltime (up to now: {num_cpus*config['system'][data['job']['system'].upper()][data["job"]["queue"]]['cores']*float(data['job']['runtime']):.2f})</b>
"""
    else:
      tables += f"""
      <div style="margin: 15px">
      <b>This job has used approximately {num_cpus} nodes &times; {config['system'][data['job']['system'].upper()][data["job"]["queue"]]['cores']} cores &times; {float(data['job']['runtime']):.3f} hours = {num_cpus*config['system'][data['job']['system'].upper()][data["job"]["queue"]]['cores']*float(data['job']['runtime']):.2f} core-h up to now</b>
"""
    if config['energy']:
      tables += f"""
      <br />
      <b>Estimated energy used by this job up to now, integrated from the node power snapshots: {data['energy']['en_nd_all_sum']:.2f} M-Joules = {data['energy']['en_nd_all_sum']*0.2778:.2f} kWh</b>
"""
    tables += f"""
    </div>
"""

  if config['appearance'].get('hostname'):
      hostname_link = f"{replace_vars(config['appearance']['hostname'], data['job'])}/login.php"
  else:
      hostname_link = config['appearance'].get('standalone_link')

  navbar = f"""
    <div id="navbar" class="no-print">
      <table style="border: 0px solid black; width: 100%;">
        <tr>
          <td rowspan="2" style="width:6%; text-align:center; padding: 0 0 0 20px; vertical-align:middle;">
            <div class="tooltip">
              <a href="{data['files']['pdffile']}" class="pdf">
              <i class="fa fa-file-pdf-o fa-2x" aria-hidden="true"></i></a>
              <span class="tooltiptext">Download PDF</span>
            </div>
          </td>
          <td rowspan="2" style="width:4%; text-align:center; padding: 0 20px 0 0; vertical-align:middle">
            <div class="tooltip">
              <a href="javascript:void(0);" onclick="return download_data('job-{data['job']['system']}-{data['job']['jobid']}.json');" class="pdf">	
              <i class="fa fa-file-text-o fa-2x" aria-hidden="true"></i>
              </a>
              <span class="tooltiptext">Download Data</span>
            </div>
          </td>
          <td rowspan="2">
            <div class="lockzoom">
              <div style="text-align:center;" class="tooltip">
                <label for="lockzoom" id="lockzoom-label">
                  <i style="font-size: 12px;" class="fa fa-search-plus" aria-hidden="true"></i>
                  <br />
                </label>
                <input type="checkbox" class="flipswitch" data-on-text="&#xf023;" data-off-text="&#xf09c;" id="lockzoom" />
                <span class="tooltiptext">Zoom-Lock (Graphs within a section, Timeline with all)</span>
              </div>
            </div>
          </td>
          <td style="text-align: center;"><b>{data['job']['system'].replace('_',' ')}</b></td>
          <td style="text-align: center;">Queue: <b>{data['job']['queue']}</b></td>
          <td style="text-align: center;">#Nodes: <b>{data['job']['numnodes']}</b></td>
          <td style="text-align: center;">{"#GPUs: <b>"+str(data['job']['numgpus'])+"</b>" if gpus else ""}</td>
          <td style="text-align: center;">Last Update: <b>{data['job']['updatetime']}</b></td>
          <td rowspan="2" style="width:6%; padding: 0px; vertical-align:middle;">
            <a href="{hostname_link}" class="simple">
            <div style="position: relative;">
              <svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="0 0 940 555"  height="40px" style="fill-rule:evenodd;" xmlns:xlink="http://www.w3.org/1999/xlink">
                <g><path style="opacity:0.991" fill="#163b67" d="M 20.5,14.5 C 39.8333,14.5 59.1667,14.5 78.5,14.5C 78.5,140.833 78.5,267.167 78.5,393.5C 90.8333,393.5 103.167,393.5 115.5,393.5C 115.5,297.167 115.5,200.833 115.5,104.5C 134.833,104.5 154.167,104.5 173.5,104.5C 173.5,200.833 173.5,297.167 173.5,393.5C 212.167,393.5 250.833,393.5 289.5,393.5C 289.5,410.833 289.5,428.167 289.5,445.5C 250.833,445.5 212.167,445.5 173.5,445.5C 173.5,457.833 173.5,470.167 173.5,482.5C 243.833,482.5 314.167,482.5 384.5,482.5C 384.5,500.167 384.5,517.833 384.5,535.5C 294.833,535.5 205.167,535.5 115.5,535.5C 115.5,505.5 115.5,475.5 115.5,445.5C 83.5,445.5 51.5,445.5 19.5,445.5C 19.1684,301.763 19.5017,158.097 20.5,14.5 Z"/></g>
                <g><path style="opacity:0.977" fill="#163b67" d="M 212.5,171.5 C 224.186,171.168 235.852,171.501 247.5,172.5C 265.374,220.623 282.54,268.957 299,317.5C 316.076,268.771 333.242,220.105 350.5,171.5C 362.186,171.168 373.852,171.501 385.5,172.5C 362.098,234.539 338.598,296.539 315,358.5C 304.333,359.833 293.667,359.833 283,358.5C 259.195,296.248 235.695,233.914 212.5,171.5 Z"/></g>
                <g><path style="opacity:0.973" fill="#163b67" d="M 411.5,171.5 C 422.833,171.5 434.167,171.5 445.5,171.5C 445.5,234.167 445.5,296.833 445.5,359.5C 434.167,359.5 422.833,359.5 411.5,359.5C 411.5,296.833 411.5,234.167 411.5,171.5 Z"/></g>
                <g><path style="opacity:0.951" fill="#163b67" d="M 411.5,100.5 C 422.833,100.5 434.167,100.5 445.5,100.5C 445.5,113.167 445.5,125.833 445.5,138.5C 434.167,138.5 422.833,138.5 411.5,138.5C 411.5,125.833 411.5,113.167 411.5,100.5 Z"/></g>
                <g><path style="opacity:0.98" fill="#163b67" d="M 556.5,167.5 C 591.851,163.538 619.684,175.871 640,204.5C 651.674,226.366 656.507,249.699 654.5,274.5C 608.167,274.5 561.833,274.5 515.5,274.5C 515.803,293.927 522.803,310.427 536.5,324C 555.742,338.52 576.075,340.187 597.5,329C 607.888,321.273 615.222,311.273 619.5,299C 630.539,299.254 641.539,300.254 652.5,302C 647.664,328.535 632.664,347.201 607.5,358C 590.543,363.205 573.21,364.872 555.5,363C 511.43,355.26 486.93,329.093 482,284.5C 479.584,262.286 481.918,240.619 489,219.5C 501.805,189.523 524.305,172.189 556.5,167.5 Z M 567.5,194.5 C 599.44,197.107 616.773,214.44 619.5,246.5C 585.5,246.5 551.5,246.5 517.5,246.5C 520.727,215.929 537.394,198.596 567.5,194.5 Z"/></g>
                <g><path style="opacity:0.977" fill="#163b67" d="M 669.5,171.5 C 680.853,171.168 692.186,171.501 703.5,172.5C 716.821,220.117 729.988,267.784 743,315.5C 756.148,267.573 768.982,219.573 781.5,171.5C 793.167,171.5 804.833,171.5 816.5,171.5C 827.764,218.449 839.931,265.115 853,311.5C 866.679,265.115 880.513,218.782 894.5,172.5C 905.146,171.501 915.813,171.168 926.5,171.5C 907.958,233.66 888.791,295.66 869,357.5C 857.419,359.466 845.586,360.133 833.5,359.5C 821.162,312.982 809.329,266.315 798,219.5C 785.315,266.051 773.148,312.717 761.5,359.5C 749.586,359.821 737.753,359.488 726,358.5C 706.45,296.352 687.616,234.019 669.5,171.5 Z"/></g>
              </svg>
            </div>
            </a>
          </td>
        </tr>
        <tr>
          <td style="text-align: center;">Job ID: <b>{data['job']['jobid']}</b></td>
          <td style="text-align: center;">User: <b>{data['job']['owner']}</b></td>
          <td style="text-align: center;" colspan="2">Project: <b>{data['job']['account']}</b></td>
          <td style="text-align: center;">Job Name: <b>{data['job']['name']}</b></td>
        </tr>
      </table>
    </div>
"""
  return tables,navbar

