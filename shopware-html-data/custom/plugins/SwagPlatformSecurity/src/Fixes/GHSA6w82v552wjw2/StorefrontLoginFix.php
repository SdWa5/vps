<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA6w82v552wjw2;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('framework')]
class StorefrontLoginFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-6w82-v552-wjw2';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.4.6.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.5.1';
    }
}
