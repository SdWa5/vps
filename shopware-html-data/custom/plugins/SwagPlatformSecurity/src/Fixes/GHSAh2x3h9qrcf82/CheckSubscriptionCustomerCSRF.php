<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAh2x3h9qrcf82;

use Swag\Security\Components\AbstractSecurityFix;

class CheckSubscriptionCustomerCSRF extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-h2x3-h9qr-cf82';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.0.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.3.1';
    }
}
