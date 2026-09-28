<?php
// Dynamic property assignments in app/code, found by reflection so that properties declared on
// a parent class are not reported. Run from the Magento root: php < dynprops.php
require getcwd() . '/vendor/autoload.php';

$hits = [];
$scanned = 0;
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator(getcwd() . '/app/code')) as $f) {
    if ($f->getExtension() !== 'php' || str_contains($f->getPathname(), '/Test/')) {
        continue;
    }
    $src = file_get_contents($f->getPathname());
    if (!preg_match('/^namespace\s+([^;]+);/m', $src, $ns)
        || !preg_match('/^(?:abstract\s+|final\s+|readonly\s+)*class\s+(\w+)/m', $src, $cn)
        || !preg_match_all('/\$this->(\w+)\s*=[^=]/', $src, $m)) {
        continue;
    }
    $class = $ns[1] . '\\' . $cn[1];
    $scanned++;
    try {
        $rc = new ReflectionClass($class);
    } catch (Throwable $e) {
        $hits[] = "$class: cannot reflect: " . $e->getMessage();
        continue;
    }
    if ($rc->hasMethod('__set') || $rc->getAttributes('AllowDynamicProperties')
        || $rc->isSubclassOf(Magento\Framework\DataObject::class)) {
        continue;
    }
    $declared = [];
    for ($c = $rc; $c; $c = $c->getParentClass()) {
        foreach ($c->getProperties() as $p) {
            $declared[$p->getName()] = true;
        }
    }
    foreach (array_unique($m[1]) as $prop) {
        if (!isset($declared[$prop])) {
            $hits[] = "$class::\$$prop  " . substr($f->getPathname(), strlen(getcwd()) + 1);
        }
    }
}
echo implode("\n", $hits), $hits ? "\n" : '', count($hits), " dynamic property assignment(s) in $scanned classes\n";
