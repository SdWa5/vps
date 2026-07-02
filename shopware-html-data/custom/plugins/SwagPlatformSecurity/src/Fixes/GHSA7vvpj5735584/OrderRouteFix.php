<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA7vvpj5735584;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('checkout')]
class OrderRouteFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-7vvp-j573-5584';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.8.1';
    }
}
