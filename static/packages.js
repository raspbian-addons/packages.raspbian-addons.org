
function init_toggle_elem(id_str,user_str) {
	toggle_toggle_elem(id_str,user_str,'hide');
}

function toggle_toggle_elem(id_str,user_str,mode) {
	var other_mode = ( mode == "hide" ) ? "show" : "hide";
	var link = document.createElement("a");
	link.setAttribute("href","javascript:toggle_toggle_elem(\""+id_str+"\",\""+user_str+"\",\""+other_mode+"\")");
	var txt = document.createTextNode("["+other_mode+" "+user_str+"]");
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
