<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAc4p7rwrgpf6p\ChangeResolver;

use Shopware\Core\Framework\App\AppCollection;
use Shopware\Core\Framework\App\AppEntity;
use Shopware\Core\Framework\App\Lifecycle\Registration\AppRegistrationService;
use Shopware\Core\Framework\App\Manifest\Manifest;
use Shopware\Core\Framework\App\ShopId\ShopIdProvider;
use Shopware\Core\Framework\App\Source\SourceResolver;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\Log\Package;
use Swag\Security\Fixes\GHSAc4p7rwrgpf6p\AppSecretRotationService;

#[Package('framework')]
class MoveShopPermanentlyStrategy extends \Shopware\Core\Framework\App\ShopIdChangeResolver\MoveShopPermanentlyStrategy
{
    /**
     * @param EntityRepository<AppCollection> $appRepository
     */
    public function __construct(
        SourceResolver $sourceResolver,
        EntityRepository $appRepository,
        AppRegistrationService $registrationService,
        private readonly ShopIdProvider $shopIdProvider,
        private readonly AppSecretRotationService $appSecretRotationService
    ) {
        /** @phpstan-ignore argument.type */
        parent::__construct($sourceResolver, $appRepository, $registrationService, $shopIdProvider);
    }

    public function resolve(Context $context): void
    {
        try {
            $this->shopIdProvider->reset();
            $this->shopIdProvider->getShopId();

            // no resolution needed
            return;
        } catch (\Shopware\Core\Framework\App\Exception\ShopIdChangeSuggestedException $e) {
            $this->shopIdProvider->regenerateAndSetShopId($e->shopId->id);
        }

        $this->forEachInstalledApp($context, function (Manifest $manifest, AppEntity $app, Context $context): void {
            $this->appSecretRotationService->rotateNow($app->getId(), $context, AppSecretRotationService::TRIGGER_SHOP_MOVE);
        });
    }
}
