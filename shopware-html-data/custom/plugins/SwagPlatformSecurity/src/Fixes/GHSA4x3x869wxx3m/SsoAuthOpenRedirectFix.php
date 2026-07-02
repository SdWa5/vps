<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA4x3x869wxx3m;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('framework')]
class SsoAuthOpenRedirectFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-4x3x-869w-xx3m';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.3.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.10.1';
    }
}
