<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAc4p7rwrgpf6p\ChangeResolver;

use Shopware\Core\DevOps\Environment\EnvironmentHelper;
use Shopware\Core\Framework\App\AppCollection;
use Shopware\Core\Framework\App\AppEntity;
use Shopware\Core\Framework\App\Exception\AppUrlChangeDetectedException;
use Shopware\Core\Framework\App\Lifecycle\Registration\AppRegistrationService;
use Shopware\Core\Framework\App\Manifest\Manifest;
use Shopware\Core\Framework\App\ShopId\ShopIdProvider;
use Shopware\Core\Framework\App\Source\SourceResolver;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\DataAbstractionLayer\EntityRepository;
use Shopware\Core\Framework\Log\Package;
use Swag\Security\Fixes\GHSAc4p7rwrgpf6p\AppSecretRotationService;

if (class_exists(\Shopware\Core\Framework\App\AppUrlChangeResolver\MoveShopPermanentlyStrategy::class)) {
    #[Package('framework')]
    class MoveShopPermanentlyStrategyPre6730 extends \Shopware\Core\Framework\App\AppUrlChangeResolver\MoveShopPermanentlyStrategy
    {
        /**
         * @param EntityRepository<AppCollection> $appRepository
         */
        public function __construct(
            SourceResolver $sourceResolver,
            EntityRepository $appRepository,
            AppRegistrationService $registrationService,
            private readonly ShopIdProvider $shopIdProvider,
            private readonly AppSecretRotationService $appSecretRotationService,
            private readonly string $shopwareVersion
        ) {
            parent::__construct($sourceResolver, $appRepository, $registrationService, $shopIdProvider); /** @phpstan-ignore constructor.call, class.noParent */
        }

        public function resolve(Context $context): void
        {
            if (version_compare($this->shopwareVersion, '6.7.2.0', '>=')) {
                $this->v6720($context);
            } else {
                $this->v6700($context);
            }
        }

        private function v6720(Context $context): void
        {
            try {
                $this->shopIdProvider->getShopId();

                // no resolution needed
                return;
            } catch (AppUrlChangeDetectedException $e) { /** @phpstan-ignore class.notFound  */
                $this->shopIdProvider->regenerateAndSetShopId($e->getShopId()->id); /** @phpstan-ignore class.notFound, typePerfect.noMixedPropertyFetcher */
            }

            $this->forEachInstalledApp($context, function (Manifest $manifest, AppEntity $app, Context $context): void { /** @phpstan-ignore method.notFound */
                $this->appSecretRotationService->rotateNow($app->getId(), $context, AppSecretRotationService::TRIGGER_SHOP_MOVE);
            });
        }

        private function v6700(Context $context): void
        {
            try {
                $this->shopIdProvider->getShopId();

                // no resolution needed
                return;
            } catch (AppUrlChangeDetectedException $e) { /** @phpstan-ignore class.notFound  */
                $this->shopIdProvider->setShopId($e->getShopId(), (string) EnvironmentHelper::getVariable('APP_URL')); /** @phpstan-ignore class.notFound, method.private, arguments.count */
            }

            $this->forEachInstalledApp($context, function (Manifest $manifest, AppEntity $app, Context $context): void { /** @phpstan-ignore method.notFound */
                $this->appSecretRotationService->rotateNow($app->getId(), $context, AppSecretRotationService::TRIGGER_SHOP_MOVE);
            });
        }
    }
}
