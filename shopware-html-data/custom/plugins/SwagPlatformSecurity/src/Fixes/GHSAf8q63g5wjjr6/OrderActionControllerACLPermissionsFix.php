<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAf8q63g5wjjr6;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('checkout')]
class OrderActionControllerACLPermissionsFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-f8q6-3g5w-jjr6';
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
