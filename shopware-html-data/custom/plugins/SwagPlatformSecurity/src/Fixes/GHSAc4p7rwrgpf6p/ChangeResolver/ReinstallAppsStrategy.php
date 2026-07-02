<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAc4p7rwrgpf6p\ChangeResolver;

use Shopware\Core\Framework\App\AppEntity;
use Shopware\Core\Framework\App\Event\AppInstalledEvent;
use Shopware\Core\Framework\App\Lifecycle\Registration\AppRegistrationService;
use Shopware\Core\Framework\App\Manifest\Manifest;
use Shopware\Core\Framework\App\ShopId\ShopIdProvider;
use Shopware\Core\Framework\App\Source\SourceResolver;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\Log\Package;
use Swag\Security\Fixes\GHSAc4p7rwrgpf6p\AppSecretRotationService;
use Symfony\Contracts\EventDispatcher\EventDispatcherInterface;

#[Package('framework')]
class ReinstallAppsStrategy extends \Shopware\Core\Framework\App\ShopIdChangeResolver\ReinstallAppsStrategy
{
    public function __construct(
        SourceResolver $sourceResolver,
        EntityRepository $appRepository,
        AppRegistrationService $registrationService,
        private readonly ShopIdProvider $shopIdProvider,
        private readonly EventDispatcherInterface $eventDispatcher,
        private readonly AppSecretRotationService $appSecretRotationService
    ) {
        /** @phpstan-ignore argument.type */
        parent::__construct($sourceResolver, $appRepository, $registrationService, $this->shopIdProvider, $this->eventDispatcher);
    }

    public function resolve(Context $context): void
    {
        $this->shopIdProvider->deleteShopId();

        $this->forEachInstalledApp($context, function (Manifest $manifest, AppEntity $app, Context $context): void {
            $this->appSecretRotationService->rotateNow($app->getId(), $context, AppSecretRotationService::TRIGGER_SHOP_MOVE);
            $this->eventDispatcher->dispatch(
                new AppInstalledEvent($app, $manifest, $context)
            );
        });
    }
}
