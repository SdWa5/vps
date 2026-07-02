<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAxvhcgm7jmhmc;

use Shopware\Core\Content\Media\File\FileSaver;
use Shopware\Core\Content\Media\File\MediaFile;
use Shopware\Core\Content\Media\MediaException;
use Shopware\Core\Framework\Context;
use Shopware\Core\Framework\Log\Package;

#[Package('discovery')]
class FileSaverDecorator extends FileSaver
{
    public function __construct(
        private readonly FileSaver $inner,
        private readonly SvgContentValidator $svgContentValidator,
    ) {
        // Intentionally skip parent::__construct: all parent behavior is proxied to $inner,
        // so the parent's readonly services (repositories, filesystems, etc.) remain untouched.
    }

    public function getDecorated(): FileSaver
    {
        return $this->inner;
    }

    /**
     * @throws MediaException
     */
    public function persistFileToMedia(
        MediaFile $mediaFile,
        string $destination,
        string $mediaId,
        Context $context
    ): void {
        $this->svgContentValidator->validate($mediaFile);

        $this->inner->persistFileToMedia($mediaFile, $destination, $mediaId, $context);
    }

    public function renameMedia(string $mediaId, string $destination, Context $context): void
    {
        $this->inner->renameMedia($mediaId, $destination, $context);
    }
}
