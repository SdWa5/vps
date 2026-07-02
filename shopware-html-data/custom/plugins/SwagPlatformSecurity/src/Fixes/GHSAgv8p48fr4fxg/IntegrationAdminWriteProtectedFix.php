<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAgv8p48fr4fxg;

use Shopware\Core\Framework\Log\Package;
use Shopware\Core\System\Integration\IntegrationDefinition;
use Swag\Security\Components\AbstractSecurityFix;
use Symfony\Component\DependencyInjection\ContainerBuilder;

#[Package('framework')]
class IntegrationAdminWriteProtectedFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-gv8p-48fr-4fxg';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.10.1';
    }

    public static function buildContainer(ContainerBuilder $container): void
    {
        $container->getDefinition(IntegrationDefinition::class)->setClass(PatchedIntegrationDefinition::class);
    }
}
