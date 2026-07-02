<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAgqc5xv7mgcjq;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('checkout')]
class LoginRouteFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-gqc5-xv7m-gcjq';
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
