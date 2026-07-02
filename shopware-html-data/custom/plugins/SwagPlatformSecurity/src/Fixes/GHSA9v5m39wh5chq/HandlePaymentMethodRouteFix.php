<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA9v5m39wh5chq;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('checkout')]
class HandlePaymentMethodRouteFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-9v5m-39wh-5chq';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.10.1';
    }
}
