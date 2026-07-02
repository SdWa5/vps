<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA27c9vp3w6ww8;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('after-sales')]
class SensitiveDataExportFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-27c9-vp3w-6ww8';
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
