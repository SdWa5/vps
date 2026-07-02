<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA7w527jvmm9vw;

use Shopware\Core\Framework\Api\OAuth\ClientRepository;
use Shopware\Core\Framework\Api\OAuth\UserRepository;
use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Sso\Config\LoginConfigService;
use Swag\Security\Components\AbstractSecurityFix;
use Symfony\Component\DependencyInjection\ContainerBuilder;

#[Package('framework')]
class OAuthRepositoriesFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-7w52-7jvm-m9vw';
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
        $container->getDefinition(ClientRepository::class)
            ->setClass(PatchedClientRepository::class);

        $patchedUserRepositoryClass = class_exists(LoginConfigService::class)
            ? PatchedUserRepository::class
            : PatchedUserRepositoryPre672::class;

        $container->getDefinition(UserRepository::class)
            ->setClass($patchedUserRepositoryClass);
    }
}
