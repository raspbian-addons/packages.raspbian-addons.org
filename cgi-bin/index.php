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

$SUITES = array('oldstable', 'stable', 'testing', 'unstable', 'experimental');
$pi = substr($_SERVER["PATH_INFO"], 1);
$elems = explode('/', $pi);
if ($pi == "") {
	readfile("index.html");
	exit;
} elseif ($pi == 'search') {
	go("search_packages.pl");
} elseif ($elems[0] == 'package' && count($elems) == 2) {
	$_GET['searchon'] = 'names';
	$_GET['keywords'] = $elems[1];
	$_GET['suite'] = 'all';
	$_GET['exact'] = 1;
	go("search_packages.pl");
} elseif ($elems[0] == 'source' && count($elems) == 2) {
	$_GET['searchon'] = 'sourcenames';
	$_GET['keywords'] = $elems[1];
	$_GET['suite'] = 'all';
	$_GET['exact'] = 1;
	go("search_packages.pl");
} elseif (in_array($elems[0], $SUITES) && count($elems) == 2) {
	$_GET['package'] = $elems[1];
	$_GET['suite'] = $elems[0];
	go("show_package.pl");
} elseif (in_array($elems[0], $SUITES) && count($elems) == 3) {
	header("Location: http://merkel.debian.org/~jeroen/pdo/$elems[0]/".urlencode($elems[2]));
	exit;
} elseif (substr($pi, 0, 4) == 'src:') {
	header("Location: http://merkel.debian.org/~jeroen/pdo/source/".urlencode(substr($pi,4)));
	exit;
} elseif (!eregi('[^a-z0-9+.-]', $pi)) {
	header("Location: http://merkel.debian.org/~jeroen/pdo/package/".urlencode($pi));
	exit;
} else {
	echo "404 not found";
}
