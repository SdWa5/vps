<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAgq965pfxf4vc;

use Shopware\Core\Content\Media\File\FileUrlValidatorInterface;
use Shopware\Core\Content\Media\Upload\MediaUploadService;
use Shopware\Core\Framework\Log\Package;
use Swag\Security\Components\AbstractSecurityFix;
use Symfony\Component\DependencyInjection\ContainerBuilder;
use Symfony\Component\DependencyInjection\Reference;

#[Package('discovery')]
class MediaUploadServiceFix extends AbstractSecurityFix
{
    public static function getTicket(): string
    {
        return 'GHSA-gq96-5pfx-f4vc';
    }

    public static function getLowestAffectedShopwareVersion(): string
    {
        return '6.7.1.0';
    }

    public static function getShopwareVersionWhereThisIssueWasFixed(): string
    {
        return '6.7.10.1';
    }

    public static function buildContainer(ContainerBuilder $container): void
    {
        $definition = $container->getDefinition(MediaUploadService::class);
        $definition->setClass(PatchedMediaUploadService::class);
        $definition->setArguments([
            new Reference(FileUrlValidatorInterface::class),
            '%shopware.media.enable_url_validation%',
            ...array_values($definition->getArguments()),
        ]);
    }
}
