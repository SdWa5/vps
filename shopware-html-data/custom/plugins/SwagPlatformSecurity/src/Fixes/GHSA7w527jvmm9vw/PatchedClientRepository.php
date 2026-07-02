<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA7w527jvmm9vw;

use Doctrine\DBAL\Connection;
use League\OAuth2\Server\Entities\ClientEntityInterface;
use League\OAuth2\Server\Exception\OAuthServerException;
use Shopware\Core\Framework\Api\OAuth\ClientRepository;
use Shopware\Core\Framework\Api\Util\AccessKeyHelper;
use Shopware\Core\Framework\Log\Package;

/**
 * Prevents client enumeration via timing attacks.
 *
 * When no record is found, password_verify is still executed against a static
 * dummy hash so that the failure path takes roughly the same time as a
 * real-but-wrong-credentials path.
 */
#[Package('framework')]
class PatchedClientRepository extends ClientRepository
{
    /**
     * Bcrypt hash for a static dummy secret used to equalize timing when no client is found.
     */
    private const DUMMY_CLIENT_SECRET_HASH = '$2y$12$PVcA5R6ri9kS.7FnFUBRIOLwqU//bCicx5RFxwecAAccbmZ7V7PKu';

    private readonly Connection $innerConnection;

    public function __construct(
        Connection $connection,
        mixed ...$clientRepositoryArguments,
    ) {
        parent::__construct($connection, ...$clientRepositoryArguments);
        $this->innerConnection = $connection;
    }

    public function validateClient(string $clientIdentifier, ?string $clientSecret, ?string $grantType): bool
    {
        if (($grantType === 'password' || $grantType === 'refresh_token') && $clientIdentifier === 'administration') {
            return true;
        }

        if ($grantType === 'client_credentials' && $clientSecret !== null) {
            $values = $this->getByAccessKey($clientIdentifier);

            if (!$values) {
                // Prevent client enumeration via timing attacks by always running password_verify().
                $values = ['secret_access_key' => self::DUMMY_CLIENT_SECRET_HASH];
                $clientSecret = 'invalid-secret-will-always-fail';
            }

            if (!password_verify($clientSecret, (string) $values['secret_access_key'])) {
                return false;
            }

            $id = $values['id'] ?? '';
            if ($id !== '') {
                $this->updateLastUsageDate($id);
            }

            return true;
        }

        // @codeCoverageIgnoreStart
        throw OAuthServerException::unsupportedGrantType();
        // @codeCoverageIgnoreEnd
    }

    public function getClientEntity(string $clientIdentifier): ?ClientEntityInterface
    {
        $client = parent::getClientEntity($clientIdentifier);

        if ($client === null) {
            // Prevent client enumeration via timing attacks by always running password_verify().
            password_verify('invalid-secret-will-always-fail', self::DUMMY_CLIENT_SECRET_HASH);
        }

        return $client;
    }

    /**
     * Parent method is private, so we redefine it here for our override.
     *
     * @return array{user_id: string, secret_access_key: string}|array{id: string, label: string, secret_access_key: string}|null
     */
    private function getByAccessKey(string $clientIdentifier): ?array
    {
        $origin = AccessKeyHelper::getOrigin($clientIdentifier);

        if ($origin === 'user') {
            return $this->getUserByAccessKey($clientIdentifier);
        }

        if ($origin === 'integration') {
            return $this->getIntegrationByAccessKey($clientIdentifier);
        }

        return null;
    }

    /**
     * Parent method is private, so we redefine it here for our override.
     *
     * @return array{user_id: string, secret_access_key: string}|null
     */
    private function getUserByAccessKey(string $clientIdentifier): ?array
    {
        /** @var array{user_id: string, secret_access_key: string}|false $key */
        $key = $this->innerConnection->fetchAssociative(
            'SELECT user_id, secret_access_key
             FROM user_access_key
             WHERE access_key = :accessKey',
            ['accessKey' => $clientIdentifier]
        );

        if ($key === false) {
            return null;
        }

        return $key;
    }

    /**
     * Parent method is private, so we redefine it here for our override.
     *
     * @return array{id: string, label: string, secret_access_key: string}|null
     */
    private function getIntegrationByAccessKey(string $clientIdentifier): ?array
    {
        /** @var array{id: string, label: string, active: '1'|'0', secret_access_key: string}|false $key */
        $key = $this->innerConnection->fetchAssociative(
            'SELECT integration.id AS id, label, app.active AS active, secret_access_key
             FROM integration
             LEFT JOIN app ON app.integration_id = integration.id
             WHERE access_key = :accessKey',
            ['accessKey' => $clientIdentifier]
        );

        if ($key === false) {
            return null;
        }

        // inactive apps cannot access the api
        // if the integration is not associated to an app `active` will be null
        if ($key['active'] === '0') {
            return null;
        }
        unset($key['active']);

        return $key;
    }
}
