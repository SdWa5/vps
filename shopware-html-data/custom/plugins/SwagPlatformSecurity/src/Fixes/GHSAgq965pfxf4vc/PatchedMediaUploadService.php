<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAgq965pfxf4vc;

use Shopware\Core\Content\Media\File\FileUrlValidatorInterface;
use Shopware\Core\Content\Media\MediaException;
use Shopware\Core\Content\Media\Thumbnail\ExternalThumbnailCollection;
use Shopware\Core\Content\Media\Upload\MediaUploadParameters;
use Shopware\Core\Content\Media\Upload\MediaUploadService;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\Log\Package;

/**
 * @internal
 *
 * Patches GHSA-gq96-5pfx-f4vc: validates external URLs against private/reserved IP ranges before the service issues a
 * HEAD request or stores them. Applies to the external-link and external-thumbnails endpoints.
 */
// @phpstan-ignore class.extendsFinalByPhpDoc (intentional extension of @final class for security patch)
#[Package('discovery')]
readonly class PatchedMediaUploadService extends MediaUploadService
{
    public function __construct(
        private FileUrlValidatorInterface $fileUrlValidator,
        private bool $enableUrlValidation = true,
        mixed ...$mediaUploadServiceArguments,
    ) {
        parent::__construct(...$mediaUploadServiceArguments);
    }

    public function linkURL(
        string $url,
        Context $context,
        MediaUploadParameters $params = new MediaUploadParameters()
    ): string {
        $this->assertValidUrl($url);

        return parent::linkURL($url, $context, $params);
    }

    public function addExternalThumbnailsToMedia(string $mediaId, ExternalThumbnailCollection $thumbnails, Context $context): void
    {
        foreach ($thumbnails as $thumbnail) {
            $this->assertValidUrl($thumbnail->url);
        }

        parent::addExternalThumbnailsToMedia($mediaId, $thumbnails, $context);
    }

    private function assertValidUrl(string $url): void
    {
        // @phpstan-ignore function.alreadyNarrowedType (always true on trunk, needed for released versions without isExternalUrl)
        $isExternal = method_exists(parent::class, 'isExternalUrl')
            ? parent::isExternalUrl($url)
            : (bool) preg_match('/^https?:\/\/.+/', $url);

        if (!$isExternal) {
            throw MediaException::illegalUrl($url);
        }

        if ($this->enableUrlValidation && !$this->fileUrlValidator->isValid($url)) {
            throw MediaException::illegalUrl($url);
        }
    }
}
