<?php declare(strict_types=1);

namespace Swag\Security\Components;

use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\Struct\Struct;
use Symfony\Component\DependencyInjection\ContainerBuilder;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * @internal
 */
#[Package('framework')]
abstract class AbstractSecurityFix extends Struct implements EventSubscriberInterface
{
    abstract public static function getTicket(): string;

    abstract public static function getLowestAffectedShopwareVersion(): string;

    public static function isValidForVersion(string $version): bool
    {
        if (version_compare(static::getLowestAffectedShopwareVersion(), $version, '>')) {
            return false;
        }

        if (version_compare(static::getShopwareVersionWhereThisIssueWasFixed(), $version, '<=')) {
            return false;
        }

        return true;
    }

    abstract public static function getShopwareVersionWhereThisIssueWasFixed(): string;

    public static function getSubscribedEvents(): array
    {
        return [];
    }

    /**
     * Executed on any plugin boot
     */
    public static function boot(ContainerInterface $container): void
    {
    }

    public static function buildContainer(ContainerBuilder $container): void
    {
    }
}
