<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAr2vghvjmfg38;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('checkout')]
class CancelOrderRouteFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-r2vg-hvjm-fg38';
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
