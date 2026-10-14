<?php

declare(strict_types=1);

define('SDWA5_DATABASE_CLIENT_LIBRARY', true);
require __DIR__.'/../monitoring/shopware-database-client.php';

$parameters = [
    'driver' => 'pdo_mysql',
    'host' => '127.0.0.1',
    'port' => 3306,
    'user' => 'backup',
    'password' => 'test-password',
    'dbname' => 'app',
];

function verifyBackupClient(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

$dump = shopwareBackupCommand($parameters, 'dump');
verifyBackupClient('mysqldump' === $dump[0], 'The native dump client is required.');
$requiredOptions = [
    '--single-transaction', '--skip-lock-tables', '--routines',
    '--events', '--triggers', '--set-gtid-purged=OFF',
];
foreach ($requiredOptions as $option) {
    verifyBackupClient(in_array($option, $dump, true), 'The dump is missing a consistency or restore option.');
}
verifyBackupClient(!str_contains(implode(' ', $dump), 'test-password'), 'The password reached command arguments.');
verifyBackupClient(
    'mysql' === shopwareBackupCommand($parameters, 'probe')[0],
    'The metadata probe uses the wrong client.'
);
verifyBackupClient(
    str_contains(implode(' ', shopwareBackupCommand($parameters, 'probe')), 'REFERENTIAL_CONSTRAINTS'),
    'The metadata probe does not count duplicate foreign key names.'
);

$invalidCases = [
    'other' => $parameters,
    'dump' => array_replace($parameters, ['dbname' => '--other']),
];
foreach ($invalidCases as $operation => $invalid) {
    $rejected = false;
    try {
        shopwareBackupCommand($invalid, $operation);
    } catch (InvalidArgumentException|RuntimeException) {
        $rejected = true;
    }
    verifyBackupClient($rejected, 'Unsafe input was not rejected.');
}

$process = proc_open([PHP_BINARY, '-d', 'display_errors=stderr', '--', 'probe'], [
    0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w'],
], $pipes);
verifyBackupClient(is_resource($process), 'The stdin regression client could not start.');
fwrite($pipes[0], file_get_contents(__DIR__.'/../monitoring/shopware-database-client.php'));
fclose($pipes[0]);
$standardOutput = stream_get_contents($pipes[1]);
$standardError = stream_get_contents($pipes[2]);
fclose($pipes[1]);
fclose($pipes[2]);
verifyBackupClient(1 === proc_close($process), 'The missing application must fail safely.');
verifyBackupClient('' === $standardOutput, 'The failed connection wrote to the SQL stream.');
verifyBackupClient(
    str_contains($standardError, 'Connection details are not displayed.')
        && !str_contains($standardError, 'Undefined constant'),
    'Running from stdin must not depend on the STDOUT or STDERR constants.'
);

echo "Shopware database client checks passed.\n";
