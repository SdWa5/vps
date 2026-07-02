<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA7w527jvmm9vw;

use Doctrine\DBAL\Connection;
use League\OAuth2\Server\Entities\ClientEntityInterface;
use League\OAuth2\Server\Entities\UserEntityInterface;
use Shopware\Core\Framework\Api\OAuth\User\User;
use Shopware\Core\Framework\Api\OAuth\UserRepository;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Sso\Config\LoginConfigService;
use Shopware\Core\Framework\Uuid\Uuid;

/**
 * Prevents user enumeration via timing attacks.
 *
 * When no record is found, password_verify is still executed against a
 * static dummy hash so that the failure path takes roughly the same time as a
 * real-but-wrong-credentials path.
 */
#[Package('framework')]
class PatchedUserRepository extends UserRepository
{
    /**
     * Bcrypt hash for a static dummy password used to equalize timing when no user is found.
     */
    private const DUMMY_PASSWORD_HASH = '$2y$12$PVcA5R6ri9kS.7FnFUBRIOLwqU//bCicx5RFxwecAAccbmZ7V7PKu';

    public function __construct(
        private readonly Connection $innerConnection,
        private readonly LoginConfigService $innerLoginConfigService,
    ) {
    }

    public function getUserEntityByUserCredentials(
        string $username,
        #[\SensitiveParameter]
        string $password,
        string $grantType,
        ClientEntityInterface $clientEntity
    ): ?UserEntityInterface {
        if ($this->innerLoginConfigService->getConfig()?->useDefault === false) {
            // never allow login via password if the default login is disabled (e.g. using SSO only)
            return null;
        }

        $builder = $this->innerConnection->createQueryBuilder();
        $user = $builder->select('user.id', 'user.password')
            ->from('user')
            ->where('username = :username')
            ->setParameter('username', $username)
            ->fetchAssociative();

        if (!$user) {
            // Prevent user enumeration via timing attacks by always running password_verify().
            $user = ['password' => self::DUMMY_PASSWORD_HASH];
            $password = 'invalid-password-will-always-fail';
        }

        if (!password_verify($password, (string) $user['password'])) {
            return null;
        }

        return new User(Uuid::fromBytesToHex($user['id']));
    }
}
