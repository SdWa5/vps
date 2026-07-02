<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA8v9pg828v98f;

use Shopware\Core\Framework\Log\Package;
use Shopware\Core\System\User\Aggregate\UserRecovery\UserRecoveryDefinition;
use Swag\Security\Components\AbstractSecurityFix;
use Symfony\Component\DependencyInjection\ContainerBuilder;

#[Package('framework')]
class UserRecoveryFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-8v9p-g828-v98f';
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
        $container->getDefinition(UserRecoveryDefinition::class)
            ->setClass(PatchedUserRecoveryDefinition::class);
    }
}
