<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA2w46vq8h98vh;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('checkout')]
class ChangeEmailRouteFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-2w46-vq8h-98vh';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.4.1';
    }
}
