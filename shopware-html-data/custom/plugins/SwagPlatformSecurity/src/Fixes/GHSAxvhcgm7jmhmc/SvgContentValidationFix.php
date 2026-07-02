<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAxvhcgm7jmhmc;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('discovery')]
class SvgContentValidationFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-xvhc-gm7j-mhmc';
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
