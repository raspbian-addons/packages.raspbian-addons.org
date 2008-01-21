
function init_toggle_elem(id_str,show_user_str,hide_user_str) {
	toggle_toggle_elem(id_str,show_user_str,hide_user_str,'hide');
}

function toggle_toggle_elem(id_str,show_user_str,hide_user_str,mode) {
	var other_mode = ( mode == "hide" ) ? "show" : "hide";
	var user_str = ( mode == "hide" ) ? show_user_str : hide_user_str;
	var link = document.createElement("a");
	link.setAttribute("href","javascript:toggle_toggle_elem(\""+id_str+"\",\""+show_user_str+"\",\""+hide_user_str+"\",\""+other_mode+"\")");
	var txt = document.createTextNode("["+user_str+"]");
	link.appendChild(txt);
	if (document.getElementById("js_"+id_str).childNodes.length > 0) { 
		document.getElementById("js_"+id_str).replaceChild(link,document.getElementById("js_"+id_str).firstChild);
      	} else {
		document.getElementById("js_"+id_str).appendChild(link);
	}
	toggleDisplay(document.getElementById("html_"+id_str));
}

function toggleDisplay(obj) {
	if (obj.style.display == "none")
		obj.style.display = "";
	else
		obj.style.display = "none";
}

function hide_tab(id) {
	var tab = document.getElementById(id);
	if (tab) {
		tab.style.display = "none";
	}
	var item = document.getElementById(id+"link");
	if (item) {
		item.style.fontWeight = "normal";
	}
}

function show_tab(id) {
	var tab = document.getElementById(id);
	if (tab) {
		tab.style.display = "";
	}
	var item = document.getElementById(id+"link");
	if (item) {
		item.style.fontWeight = "bold";
	}
	var item = document.getElementById("palllink");
	if (item) {
		item.style.fontWeight = "normal";
	}
}

function init_tab_list(id) {
	hide_tab("pdeps");
	hide_tab("pdownload");
	show_tab("pdesctab");
	show_tab("pbinaries");

	var tablist = document.getElementById(id);
	if (tablist) {
		var list = document.createElement("ul");
		if (document.getElementById("pdesctab")) {
			var item = document.createElement("li");
			item.setAttribute("id","pdesctablink");
			var link = document.createElement("a");
			link.setAttribute("href","javascript:go_to_tab(\"pdesctab\")");
			var txt = document.createTextNode("[ Description ]");
			link.appendChild(txt);
			item.appendChild(link);
			list.appendChild(item);
		}
		if (document.getElementById("pbinaries")) {
			var item = document.createElement("li");
			item.setAttribute("id","pbinarieslink");
			var link = document.createElement("a");
			link.setAttribute("href","javascript:go_to_tab(\"pbinaries\")");
			var txt = document.createTextNode("[ Description ]");
			link.appendChild(txt);
			item.appendChild(link);
			list.appendChild(item);
		}
		if (document.getElementById("pdeps")) {
			var item = document.createElement("li");
			item.setAttribute("id","pdepslink");
			var link = document.createElement("a");
			link.setAttribute("href","javascript:go_to_tab(\"pdeps\")");
			var txt = document.createTextNode("[ Dependencies ]");
			link.appendChild(txt);
			item.appendChild(link);
			list.appendChild(item);
		}
		if (document.getElementById("pdownload")) {
			var item = document.createElement("li");
			item.setAttribute("id","pdownloadlink");
			var link = document.createElement("a");
			link.setAttribute("href","javascript:go_to_tab(\"pdownload\")");
			var txt = document.createTextNode("[ Download ]");
			link.appendChild(txt);
			item.appendChild(link);
			list.appendChild(item);
		}
		if (list.childNodes.length > 0) {
			var item = document.createElement("li");
			item.setAttribute("id","palllink");
			var link = document.createElement("a");
			link.setAttribute("href","javascript:show_all_tabs()");
			var txt = document.createTextNode("[ All ]");
			link.appendChild(txt);
			item.appendChild(link);
			list.appendChild(item);
			
		}
		tablist.appendChild(list);
	}
	show_tab("pdesctab");
	show_tab("pbinaries");
}

function go_to_tab(id) {
	if (id == "pdeps") {
		hide_tab("pdesctab");
		hide_tab("pbinaries");
		hide_tab("pdownload");
		show_tab("pdeps");
	}
	if (id == "pdesctab" || id == "pbinaries") {
		hide_tab("pdeps");
		hide_tab("pdownload");
		show_tab("pdesctab");
		show_tab("pbinaries");
	}
	if (id == "pdownload") {
		hide_tab("pdesctab");
		hide_tab("pbinaries");
		hide_tab("pdeps");
		show_tab("pdownload");
	}
}

function show_all_tabs() {
	show_tab("pdesctab");
	show_tab("pbinaries");
	show_tab("pdeps");
	show_tab("pdownload");
	var item = document.getElementById("palllink");
	if (item) {
		item.style.fontWeight = "bold";
	}
}
