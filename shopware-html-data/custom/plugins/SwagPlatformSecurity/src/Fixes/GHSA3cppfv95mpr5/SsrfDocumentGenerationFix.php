<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA3cppfv95mpr5;

use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;

#[Package('after-sales')]
class SsrfDocumentGenerationFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-3cpp-fv95-mpr5';
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
