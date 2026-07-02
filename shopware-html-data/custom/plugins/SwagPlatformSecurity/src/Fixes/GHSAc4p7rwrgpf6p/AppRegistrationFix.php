<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAc4p7rwrgpf6p;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;
use Symfony\Component\DependencyInjection\ContainerBuilder;
use Symfony\Component\DependencyInjection\Reference;

#[Package('framework')]
class AppRegistrationFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-c4p7-rwrg-pf6p';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.8.1';
    }

    public static function buildContainer(ContainerBuilder $container): void
    {
        $container->getDefinition(\Shopware\Core\Framework\App\Lifecycle\Registration\AppRegistrationService::class)
            ->setClass(AppRegistrationService::class)
            ->setArgument('$handshakeFactory', new Reference(HandshakeFactory::class));

        $container->addDefinitions([
            RotateAppSecretHandler::class => (new \Symfony\Component\DependencyInjection\Definition(RotateAppSecretHandler::class))
                ->setArgument('$rotationService', new Reference(AppSecretRotationService::class))
                ->addTag('messenger.message_handler'),
            RotateAppSecretCommand::class => (new \Symfony\Component\DependencyInjection\Definition(RotateAppSecretCommand::class))
                ->setArguments([
                    new Reference('app.repository'),
                    new Reference(AppSecretRotationService::class),
                    new Reference(\Shopware\Core\Framework\App\ActiveAppsLoader::class),
                ])
                ->addTag('console.command'),
        ]);

        if (class_exists(\Shopware\Core\Framework\App\AppUrlChangeResolver\ReinstallAppsStrategy::class)) {
            // these classes were moved in 6.7.3.0
            $container->getDefinition(\Shopware\Core\Framework\App\AppUrlChangeResolver\ReinstallAppsStrategy::class)
                ->setClass(ChangeResolver\ReinstallAppsStrategyPre6730::class)
                ->setArgument('$appSecretRotationService', new Reference(AppSecretRotationService::class))
                ->addTag('shopware.app_url_changed_resolver');

            $container->getDefinition(\Shopware\Core\Framework\App\AppUrlChangeResolver\MoveShopPermanentlyStrategy::class) /**@phpstan-ignore class.notFound */
                ->setClass(ChangeResolver\MoveShopPermanentlyStrategyPre6730::class)
                ->setArgument('$appSecretRotationService', new Reference(AppSecretRotationService::class))
                ->addTag('shopware.app_url_changed_resolver');
        } else {
            $container->getDefinition(\Shopware\Core\Framework\App\ShopIdChangeResolver\ReinstallAppsStrategy::class)
                ->setClass(ChangeResolver\ReinstallAppsStrategy::class)
                ->setArgument('$appSecretRotationService', new Reference(AppSecretRotationService::class))
                ->addTag('shopware.app_url_changed_resolver');

            $container->getDefinition(\Shopware\Core\Framework\App\ShopIdChangeResolver\MoveShopPermanentlyStrategy::class)
                ->setClass(ChangeResolver\MoveShopPermanentlyStrategy::class)
                ->setArgument('$appSecretRotationService', new Reference(AppSecretRotationService::class))
                ->addTag('shopware.app_url_changed_resolver');
        }
    }
}
