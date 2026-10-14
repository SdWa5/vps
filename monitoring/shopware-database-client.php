<?php

declare(strict_types=1);

use Doctrine\DBAL\Tools\DsnParser;
use Symfony\Component\Dotenv\Dotenv;

function shopwareBackupCommand(array $parameters, string $operation): array
{
    if ('pdo_mysql' !== ($parameters['driver'] ?? null)
        || !preg_match('/\A[A-Za-z0-9_]+\z/', $parameters['dbname'] ?? '')
        || empty($parameters['user'])) {
        throw new RuntimeException('Unsupported database connection.');
    }

    $arguments = [
        '--no-defaults',
        '--protocol=TCP',
        '--host='.($parameters['host'] ?? '127.0.0.1'),
        '--port='.($parameters['port'] ?? 3306),
        '--user='.$parameters['user'],
        '--default-character-set=utf8mb4',
    ];

    if ('probe' === $operation) {
        return array_merge(['mysql'], $arguments, [
            '--batch',
            '--skip-column-names',
            '--database='.$parameters['dbname'],
            '--execute=SELECT DATABASE(), VERSION(), COUNT(*), '
                .'COALESCE(SUM(TABLE_TYPE = \'BASE TABLE\' AND ENGINE <> \'InnoDB\'), 0) '
                .'FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()',
        ]);
    }

    if ('dump' !== $operation) {
        throw new InvalidArgumentException('Unknown database operation.');
    }

    return array_merge(['mysqldump'], $arguments, [
        '--single-transaction',
        '--quick',
        '--skip-lock-tables',
        '--no-tablespaces',
        '--set-gtid-purged=OFF',
        '--routines',
        '--events',
        '--triggers',
        '--hex-blob',
        '--databases',
        $parameters['dbname'],
    ]);
}

function runShopwareBackupClient(string $operation, string $directory): int
{
    try {
        require $directory.'/vendor/autoload.php';
        (new Dotenv())->bootEnv($directory.'/.env');
        $url = $_SERVER['DATABASE_URL'] ?? $_ENV['DATABASE_URL'] ?? getenv('DATABASE_URL');
        $parameters = (new DsnParser(['mysql' => 'pdo_mysql', 'mysql2' => 'pdo_mysql']))->parse($url);
        $environment = (array) getenv();
        $environment['MYSQL_PWD'] = $parameters['password'] ?? '';
        $process = proc_open(shopwareBackupCommand($parameters, $operation), [
            0 => ['file', '/dev/null', 'r'],
            1 => ['file', 'php://stdout', 'w'],
            2 => ['file', 'php://stderr', 'w'],
        ], $pipes, $directory, $environment);

        if (!is_resource($process)) {
            throw new RuntimeException('Database client could not start.');
        }

        return proc_close($process);
    } catch (Throwable) {
        file_put_contents('php://stderr', "The database client failed. Connection details are not displayed.\n");

        return 1;
    }
}

if (!defined('SDWA5_DATABASE_CLIENT_LIBRARY')) {
    exit(runShopwareBackupClient($argv[1] ?? '', '/var/www/html'));
}
