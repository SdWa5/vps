<?php declare(strict_types=1);

namespace Swag\Security\Api;

use Doctrine\DBAL\Connection;
use Shopware\Core\Framework\Api\Context\AdminApiSource;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\DataAbstractionLayer\Search\Criteria;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Validation\DataBag\RequestDataBag;
use Shopware\Core\System\User\UserCollection;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\Routing\Attribute\Route;

#[Route(defaults: ['_routeScope' => ['api']])]
#[Package('framework')]
class ConfigController
{
    /**
     * @param EntityRepository<UserCollection> $userRepository
     */
    public function __construct(
        private readonly Connection $connection,
        private readonly EntityRepository $userRepository
    ) {
    }

    #[Route(path: '/api/_action/swag-security/save-config')]
    public function saveConfig(RequestDataBag $requestDataBag, Context $context): JsonResponse
    {
        $this->validate($context);

        if (!$context->getSource() instanceof AdminApiSource) {
            throw new AccessDeniedHttpException('Invalid user scope');
        }

        $userId = $context->getSource()->getUserId();
        if ($userId === null) {
            throw new AccessDeniedHttpException('Invalid user scope');
        }

        $user = $this->userRepository->search(new Criteria([$userId]), $context)->first();
        if (!$user || !password_verify($requestDataBag->get('currentPassword'), $user->getPassword())) {
            throw new AccessDeniedHttpException('Invalid credentials');
        }

        $config = $requestDataBag->get('config');
        if ($config instanceof RequestDataBag) {
            foreach ($config->all() as $key => $value) {
                $this->connection->executeStatement('REPLACE INTO swag_security_config (ticket, active) VALUES (:ticket, :value)', [
                    'ticket' => $key,
                    'value' => (int) $value,
                ]);
            }
        }

        return new JsonResponse(null, Response::HTTP_NO_CONTENT);
    }

    private function validate(Context $context): void
    {
        if (!$context->getSource() instanceof AdminApiSource) {
            throw new AccessDeniedHttpException('No Privileges');
        }

        if (!$context->getSource()->isAdmin()) {
            throw new AccessDeniedHttpException('No Privileges');
        }
    }
}
