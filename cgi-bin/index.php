<?

function go($script)
{
	$pipes = null;
	$proc = proc_open("./$script php", array(
		0 => array('pipe', 'r'),
		1 => array('pipe', 'w'),
		2 => array('pipe', 'w')
		), $pipes);
	foreach ($_GET as $k => $v) {
		fwrite($pipes[0], urlencode($k)."=".urlencode($v)."\n");
	}
	fclose($pipes[0]);
	fpassthru($pipes[1]);
	$stderr = fread($pipes[2], 4096);
	$exit = proc_close($proc);
	if ($exit) {
		echo "<h1>Error happened, code $exit</h1>\n";
	}
	echo "<pre>".htmlspecialchars($stderr);
	echo "</pre>";
}
$pi = substr($_SERVER["PATH_INFO"], 1);
if ($pi == '') {
	readfile("index.html");
	exit;
} elseif ($pi == 'search') {
	go("search_packages.pl");
} elseif (substr($pi, 0, 8) == 'package/') {
	$_GET['searchon'] = 'names';
	$_GET['keywords'] = substr($pi, 8);
	$_GET['suite'] = 'all';
	$_GET['exact'] = 1;
	go("search_packages.pl");
} elseif (substr($pi, 0, 4) == 'src:') {
	header("Location: http://merkel.debian.org/~jeroen/pdo/source/".urlencode(substr($pi,4)));
} elseif (!eregi('[^a-z0-9+.-]', $pi)) {
	header("Location: http://merkel.debian.org/~jeroen/pdo/package/".urlencode($pi));
	exit;
} else {
	echo "404 not found";
}
